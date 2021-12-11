"""
Generate a system image for a VSCode environment. Intended use is as an alternative to the julia-vscode custom sysimage build system, running tests of the current project to generate precompilation statements.
"""

using PackageCompiler
using Pkg

function used_packages(env)
    project = Pkg.API.read_project(joinpath(env, "Project.toml"))
    Symbol.(collect(keys(project.deps)))
end

function generate_sysimage(env)
    mktempdir() do p
        precompile_statements_file = joinpath(p, "precompilation_statements.jl")
        sysimage_path = joinpath(env, "JuliaSysimage.so")
        generate_precompile_statements_file(env, precompile_statements_file)
        create_sysimage(used_packages(env), project=env; precompile_statements_file, sysimage_path)
    end
end

function generate_precompile_statements_file(env, file)
    p = run(`julia --project=$env --trace-compile=$file -e "using Pkg; Pkg.test()"`)
    if !success(p)
        error("Tests failed to run. Fix them before creating a new system image.")
    end
end

env = Sys.ARGS[1]
generate_sysimage(env)
