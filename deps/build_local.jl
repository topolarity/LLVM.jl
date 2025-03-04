# build a local version of LLVMExtra

using Pkg
Pkg.activate(@__DIR__)
Pkg.instantiate()

if haskey(ENV, "GITHUB_ACTIONS")
    println("::warning ::Using a locally-built LLVMExtra; A bump of LLVMExtra_jll will be required before releasing LLVM.jl.")
end

using Pkg, Scratch, Preferences, Libdl, CMake_jll, Ninja_jll

LLVM = Base.UUID("929cbde3-209d-540e-8aea-75f648917ca0")

# get scratch directories
scratch_dir = get_scratch!(LLVM, "build")
isdir(scratch_dir) && rm(scratch_dir; recursive=true)
source_dir = joinpath(@__DIR__, "LLVMExtra")

# get build directory
build_dir = if isempty(ARGS)
    mktempdir()
else
    ARGS[1]
end
mkpath(build_dir)

# download LLVM
Pkg.activate(; temp=true)
llvm_assertions = try
    cglobal((:_ZN4llvm24DisableABIBreakingChecksE, Base.libllvm_path()), Cvoid)
    false
catch
    true
end
llvm_pkg_version = "$(Base.libllvm_version.major).$(Base.libllvm_version.minor)"
LLVM = if llvm_assertions
    Pkg.add(name="LLVM_full_assert_jll", version=llvm_pkg_version)
    using LLVM_full_assert_jll
    LLVM_full_assert_jll
else
    Pkg.add(name="LLVM_full_jll", version=llvm_pkg_version)
    using LLVM_full_jll
    LLVM_full_jll
end
LLVM_DIR = joinpath(LLVM.artifact_dir, "lib", "cmake", "llvm")

# build and install
@info "Building" source_dir scratch_dir build_dir LLVM_DIR
cmake() do cmake_path
ninja() do ninja_path
    run(`$cmake_path -GNinja -DLLVM_DIR=$(LLVM_DIR) -DCMAKE_INSTALL_PREFIX=$(scratch_dir) -B$(build_dir) -S$(source_dir)`)
    run(`$ninja_path -C $(build_dir) install`)
end
end

# discover built libraries
built_libs = filter(readdir(joinpath(scratch_dir, "lib"))) do file
    endswith(file, ".$(Libdl.dlext)")
end
lib_path = joinpath(scratch_dir, "lib", only(built_libs))
isfile(lib_path) || error("Could not find library $lib_path in build directory")

# tell LLVMExtra_jll to load our library instead of the default artifact one
set_preferences!(
    joinpath(dirname(@__DIR__), "LocalPreferences.toml"),
    "LLVMExtra_jll",
    "libLLVMExtra_path" => lib_path;
    force=true,
)

# copy the preferences to `test/` as well to work around Pkg.jl#2500
cp(joinpath(dirname(@__DIR__), "LocalPreferences.toml"),
   joinpath(dirname(@__DIR__), "test", "LocalPreferences.toml"); force=true)
