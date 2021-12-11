# using ArgParse
using ArgMacros
using PackageCompiler
using Dates
using Pkg
using Crayons
using TOML

struct Sysimage
    name::Symbol
    env::Union{Nothing,String}
    packages::Vector{Symbol}
end

function packages(img::Sysimage)
    isnothing(img.env) && return img.packages
    project = Pkg.API.read_project(joinpath(img.env, "Project.toml"))
    [setdiff(Symbol.(collect(keys(project.deps))), dev_packages(img.env)); img.packages]
end

"Get all packages that are in `dev` mode for a given project environment."
function dev_packages(env::AbstractString)
    fname = joinpath(env, "Manifest.toml")
    !isfile(fname) && return Symbol[]
    devpkgs = Symbol[]
    parsed = TOML.parse(read(fname, String))
    deps = if parse(VersionNumber, get(parsed, "manifest_format", "1.0")) >= v"2.0"
        parsed["deps"]
    else
        parsed
    end
    for (key, sub) in deps
        "path" in keys(sub[1]) && push!(devpkgs, Symbol(key))
    end
    devpkgs
end

struct DefaultSysimage end

Base.dirname(::DefaultSysimage) = :default
Base.dirname(img::Sysimage) = string(img.name)
basedir(img::Sysimage) = @something(img.env, joinpath(homedir(), ".julia", "sysimages", lstrip(string(VERSION), 'v'), dirname(img)))

Base.pathof(img::DefaultSysimage) = abspath(joinpath(dirname(Sys.BINDIR), "lib", "julia", "sys.so"))
Base.pathof(img::Sysimage) = joinpath(basedir(img), "JuliaSysimage.so")

check_existing(img::Sysimage, force::Bool) = begin
    path = pathof(img)
    isfile(path) && !force && await_confirmation("A sysimage currently exists at $path. Overwrite?", true)
end

check_existing(::DefaultSysimage, args...) = true

function await_confirmation(msg::String, default; exit_on_negative=true)
    prompt = string(msg * " (", crayon"green", default ? 'Y' : 'y', crayon"reset", '/', crayon"red", !default ? 'N' : 'n', crayon"reset", ')')
    println(prompt)
    try
        while true
            answer = lowercase(strip(readline(), [' ', '\n']))
            isempty(answer) && return default
            if answer ∉ ["y", "n"]
                println("Answer not understood. ", prompt)
            elseif answer == "y"
                return true
            else
                @info "Operation aborted."
                exit_on_negative && exit(0)
                return false
            end
        end
    catch e
        if e isa InterruptException
            @info "Operation aborted."
            exit(0)
        else
            rethrow(e)
        end
    end
end

function confirm(execution_log)
    println("Summary:")
    println.(' '^4 .* split(execution_log, "\n"))
    await_confirmation("Confirm sysimage creation?", true)
end

function read_config(config_file)
    f = open(config_file, "r")
    packages = split(split(rstrip(readline(f), '\n'), "packages: ")[2], ", ")
    base_sysimage = split(rstrip(readline(f), '\n'), " ")[2]
    close(f)
    packages, base_sysimage
end

const info_filename = "info.yml"

listargs(args) = string.(filter(!isempty, split(something(args, ""), ',')))

function main()
    @inlinearguments begin
        @helpusage """


        sysimage -n test -p Test,ArgMacros             # a system image is incrementally built from the default one
        sysimage -n test2 -p Vulkan -b test            # will contain a system image with Test, ArgMacros and Vulkan
        sysimage -n test2 --rebuild                    # just rebuild the system image with the same parameters as before
        sysimage -n test2 --rebuild -r                 # make it the default system image
        sysimage --env ~/.julia/dev/SPIRV
"""
        @helpdescription """
        Utility for handling system images for the Julia programming language.

        System images provide a low-latency experience by saving the state of a program to a library (the system image), so that
        it can be reused in subsequent runs. A substantial gain comes from not having to recompile code that was compiled at the
        creation of the system image.

        """
        # sysimage --revert                           # revert any changes made to the default system image
        @argumentoptional Symbol _base_sysimage "-b" "--base-sysimage"
        @arghelp "Name of the sysimage used as a base for incrementation."
        @argumentoptional String _pkgs "-p" "--packages"
        @arghelp "Comma-separated list of packages to include in the system image."
        @argumentoptional String _execution_files "-e" "--execution-file"
        @arghelp "Comma-separated list of files containing code to be executed for triggering precompilation statements."
        @argumentoptional String _statement_files "-s" "--statements-file"
        @arghelp "Comma-separated list of files containing precompilation statements."
        @argumentflag replace_default "-r" "--replace-default"
        @arghelp "Replace default system image after creation."
        @argumentflag dry_run "-d" "--dry-run"
        @arghelp "Run without creating the system image."
        @argumentflag no_confirm "-n" "--no-confirm"
        @arghelp "Prompt user for confirmation before creating the sysimage."
        @argumentflag rebuild "--rebuild"
        @arghelp "Rebuilds the sysimage located at <name>/JuliaSysimage.so based on its info.yml file."
        @argumentflag force "-f" "--force"
        @arghelp "Force creation of a system image even if one already exists."
        @argumentoptional String env "--env"
        @arghelp "Build a system image for a custom environment, including all its dependencies (except dev'ed packages)."
        @argumentoptional Symbol name "-n" "--name"
        @arghelp "Name of the sysimage to be created."
    end

    base_sysimage = isnothing(_base_sysimage) ? DefaultSysimage() : Sysimage(_base_sysimage)
    pkgs = Symbol.(listargs(_pkgs))
    execution_files = listargs(_execution_files)
    statement_files = listargs(_statement_files)
    name = something(name, Symbol(basename(tempname())))
    target_sysimg = Sysimage(name, env, pkgs)

    target_path = pathof(target_sysimg)
    target_dir = dirname(target_path)
    mkpath(target_dir)

    if rebuild
        isnothing(env) || error("Rebuilding an image with an environment is not supported.")
        force = true
        pkgs, base_sysimage = read_config(joinpath(target_dir, info_filename))
    end

    check_existing(target_sysimg, force)

    cmd = :(
        create_sysimage(
            $(packages(target_sysimg));
            replace_default=$replace_default,
            sysimage_path=$target_path,
            incremental=true,
            base_sysimage=$(pathof(base_sysimage)),
            precompile_execution_file=$execution_files,
            precompile_statements_file=$statement_files
        ),
    )

    execution_log = """
    packages: $(join(string.(pkgs), ", "))
    sysimage_base: $(dirname(base_sysimage)) ($(pathof(base_sysimage)))
    execution_file: $(abspath.(execution_files))
    precompile_statements_file = $(abspath.(statement_files))
    command: $cmd
    """

    # Record the path of the image when built for an environment.
    !isnothing(env) && (execution_log *= "path: $target_path\n")

    if !no_confirm
        confirm(execution_log)
    end

    if !dry_run
        println(cmd)
        eval(cmd)
        write(joinpath(target_dir, "info.yml"), execution_log)
    end
end

!isinteractive() && main()
