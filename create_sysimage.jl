using ArgParse
using PackageCompiler
using Dates
using Pkg

function parse_cli()
    s = ArgParseSettings()
    @add_arg_table! s begin
        "name"
            help = "name of the sysimage to be created"
            required = true
            arg_type = String
        "-b", "--base-sysimage"
            help = "name of the sysimage used as a base for incrementation"
            arg_type = String
            default = "default"
        "-r", "--replace-default"
            help = "replace default system image after creation"
            action = :store_true
        "-p", "--packages"
            help = "list of packages for which to record precompile statements with \"using <PACKAGE>\". They are added to the environment packages if the --environment flag is provided."
            nargs = '+'
            default = nothing
        "-e", "--execution-file"
            help = "file containing code to be executed for triggering precompilation statements"
            default = String[]
        "-s", "--statements-file"
            help = "file containing precompilation statements"
            default = String[]
        "-d", "--dry-run"
            help = "run without creating the system image"
            action = :store_true
        "-n", "--no-confirm"
            help = "prompt user for confirmation before creating the sysimage"
            action = :store_true
        "--rebuild"
            help = "rebuilds the sysimage located at <name>/sysimage.so based on its info.yml file"
            action = :store_true
        "-f", "--force"
            help = "force creation of a system image even if one already exists"
            action = :store_true
    end
    args = parse_args(s)
    args["packages"] = convert(Array{String,1}, args["packages"])
    return args
end

function sysimage_path(name)
    if name == "default"
        return abspath("$(Sys.BINDIR)/../lib/julia/sys.so")
    else
        return "$(homedir())/.julia/sysimages/$name/sysimage.so"
    end
end

function make_cmd(args)
    cmd = :(create_sysimage($(map(package -> Symbol(package), args["packages"])); replace_default=$(args["replace-default"]), sysimage_path=$(sysimage_path(args["name"])), incremental=true, base_sysimage=$(sysimage_path(args["base-sysimage"])), precompile_execution_file=$(args["execution-file"]), precompile_statements_file=$(args["statements-file"])))
end

function Array{Symbol,1}(array_str::Array{String,1})
    return [Symbol(str) for str in array_str]
end



function prompt_for_confirmation()
    c = readline(stdin)
    while true
        if c in ["yes", "y"]
        break
        elseif c in ["no", "n"]
            exit(0)
        else
            println("Unknown input, please retry. (y/n)")
            c = readline(stdin, String)
        end
    end
end

function check_existing_sysimage(target_path, target_dir, force)
    if !isdir(target_dir)
        mkdir(target_dir)
    end
    if isfile(target_path) && !force
        @warn "A sysimage currently exists at $target_path. Overwrite? (y/n)"
        prompt_for_confirmation()
    end
    return
end

function confirm(execution_log)
    println("\nSummary:")
    for line in split(execution_log, "\n")
        println("    $line")
    end
    println("Confirm sysimage creation? (y/n)")
    prompt_for_confirmation()
end

function read_config(config_file)
    f = open(config_file, "r")
    packages = split(split(rstrip(readline(f), '\n'), "packages: ")[2], ", ")
    base_sysimage = split(rstrip(readline(f), '\n'), " ")[2]
    close(f)
    return ("packages" => packages, "base-sysimage" => base_sysimage)
end


args = parse_cli()

if args["rebuild"]
    args["force"] = true
    args = Dict(args..., read_config(abspath("$(sysimage_path(args["name"]))/../info.yml"))...)
end

target_path = sysimage_path(args["name"])
target_dir = abspath("$target_path/..")

check_existing_sysimage(target_path, target_dir, args["force"])

cmd = make_cmd(args)
execution_log = """
packages: $(join(args["packages"], ", "))
sysimage_base: $(args["base-sysimage"]) ($(sysimage_path(args["base-sysimage"])))
created_on: $(now())
execution_file: $(abspath.(args["execution-file"]))
precompile_statements_file = $(abspath.(args["statements-file"]))
command: $cmd
"""

if !args["no-confirm"]
    @info "Confirm configuration for new sysimage $(args["name"])"
    confirm(execution_log)
end

for pkg in args["packages"]
    @info "Importing $pkg"
    eval(Meta.parse("using $pkg"))
end

if !args["dry-run"]
    println(cmd)
    eval(cmd)
    open(target_dir * "/info.yml", "w") do f
        write(f, execution_log)
    end
end
