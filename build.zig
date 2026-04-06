const std = @import("std");
const zbh = @import("zig_build_helper");
const build_zon = @import("build.zig.zon");

comptime {
    zbh.checkZigVersion("0.15.2");
}

// Source file lists
const jpeg_sources = &[_][]const u8{
    "jcapimin.c", "jchuff.c",     "jcicc.c",    "jcinit.c",   "jclhuff.c",
    "jcmarker.c", "jcmaster.c",   "jcomapi.c",  "jcparam.c",  "jcphuff.c",
    "jctrans.c",  "jdapimin.c",   "jdatadst.c", "jdatasrc.c", "jdhuff.c",
    "jdicc.c",    "jdinput.c",    "jdlhuff.c",  "jdmarker.c", "jdmaster.c",
    "jdphuff.c",  "jdtrans.c",    "jerror.c",   "jfdctflt.c", "jmemmgr.c",
    "jmemnobs.c", "jpeg_nbits.c",
};

const turbojpeg_sources = &[_][]const u8{
    "turbojpeg.c", "transupp.c", "jdatadst-tj.c", "jdatasrc-tj.c", "rdbmp.c", "wrbmp.c",
};

const arith_sources = &[_][]const u8{"jaricom.c"};
const arith_enc_sources = &[_][]const u8{"jcarith.c"};
const arith_dec_sources = &[_][]const u8{"jdarith.c"};

// Multi-precision wrapper file bases (8, 12, 16 bit)
const wrapper_8_bases = &[_][]const u8{
    "jcapistd", "jccoefct", "jccolor",  "jcdctmgr", "jcdiffct", "jclossls",
    "jcmainct", "jcprepct", "jcsample", "jdapistd", "jdcoefct", "jdcolor",
    "jddctmgr", "jddiffct", "jdlossls", "jdmainct", "jdmerge",  "jdpostct",
    "jdsample", "jfdctfst", "jfdctint", "jidctflt", "jidctfst", "jidctint",
    "jidctred", "jquant1",  "jquant2",  "jutils",
};

const wrapper_12_bases = wrapper_8_bases; // Same files for 12-bit

const wrapper_16_bases = &[_][]const u8{
    "jcapistd", "jccolor",  "jcdiffct", "jclossls", "jcmainct", "jcprepct",
    "jcsample", "jdapistd", "jdcolor",  "jddiffct", "jdlossls", "jdmainct",
    "jdpostct", "jdsample", "jutils",
};

// Tool definitions
const ToolDef = struct {
    name: []const u8,
    sources: []const []const u8,
    wrapper_specs: []const []const u8, // Format: "base-bits" e.g. "rdppm-8"
    link_math: bool,
};

const tools = [_]ToolDef{
    .{ .name = "cjpeg", .sources = &.{ "cjpeg.c", "cdjpeg.c", "rdbmp.c", "rdgif.c", "rdswitch.c", "rdtarga.c" }, .wrapper_specs = &.{ "rdppm-8", "rdppm-12", "rdppm-16" }, .link_math = false },
    .{ .name = "djpeg", .sources = &.{ "djpeg.c", "cdjpeg.c", "rdswitch.c", "wrbmp.c", "wrtarga.c" }, .wrapper_specs = &.{ "rdcolmap-8", "rdcolmap-12", "wrgif-8", "wrgif-12", "wrppm-8", "wrppm-12", "wrppm-16" }, .link_math = false },
    .{ .name = "jpegtran", .sources = &.{ "jpegtran.c", "cdjpeg.c", "rdswitch.c", "transupp.c" }, .wrapper_specs = &.{}, .link_math = false },
    .{ .name = "rdjpgcom", .sources = &.{"rdjpgcom.c"}, .wrapper_specs = &.{}, .link_math = false },
    .{ .name = "wrjpgcom", .sources = &.{"wrjpgcom.c"}, .wrapper_specs = &.{}, .link_math = false },
};

// Version constants
const version = "3.1.0";
const jpeg_lib_version: i32 = 62;
const version_parts = parseVersion(version);
const version_number = std.fmt.comptimePrint("{d}{d:0>3}{d:0>3}", .{
    version_parts.major, version_parts.minor, version_parts.patch,
});

fn createJconfigH(
    b: *std.Build,
    upstream: *std.Build.Dependency,
    with_arith_enc: ?i32,
    with_arith_dec: ?i32,
) *std.Build.Step.ConfigHeader {
    return b.addConfigHeader(.{
        .style = .{ .cmake = upstream.path("src/jconfig.h.in") },
        .include_path = "jconfig.h",
    }, .{
        .JPEG_LIB_VERSION = jpeg_lib_version,
        .VERSION = version,
        .LIBJPEG_TURBO_VERSION_NUMBER = @as(i32, @intCast(std.fmt.parseInt(i32, version_number, 10) catch 0)),
        .C_ARITH_CODING_SUPPORTED = with_arith_enc,
        .D_ARITH_CODING_SUPPORTED = with_arith_dec,
        .WITH_SIMD = null,
        .RIGHT_SHIFT_IS_UNSIGNED = null,
    });
}

fn createJconfigintH(
    b: *std.Build,
    upstream: *std.Build.Dependency,
    platform: zbh.Platform,
    ptr_width: u16,
    with_arith_enc: ?i32,
    with_arith_dec: ?i32,
) *std.Build.Step.ConfigHeader {
    return b.addConfigHeader(.{
        .style = .{ .cmake = upstream.path("src/jconfigint.h.in") },
        .include_path = "jconfigint.h",
    }, .{
        .BUILD = "1",
        .HIDDEN = if (platform.is_windows) "" else "__attribute__((visibility(\"hidden\")))",
        .INLINE = "inline",
        .THREAD_LOCAL = if (platform.is_windows) "__declspec(thread)" else "_Thread_local",
        .CMAKE_PROJECT_NAME = "libjpeg-turbo",
        .VERSION = version,
        .SIZE_T = @as(i32, @intCast(ptr_width / 8)),
        .HAVE_BUILTIN_CTZL = zbh.Config.boolToOptInt(!platform.is_windows and platform.ptr_width == 64),
        .HAVE_INTRIN_H = zbh.Config.boolToOptInt(platform.is_windows),
        .C_ARITH_CODING_SUPPORTED = with_arith_enc,
        .D_ARITH_CODING_SUPPORTED = with_arith_dec,
        .WITH_SIMD = null,
    });
}

fn createJversionH(b: *std.Build, upstream: *std.Build.Dependency) *std.Build.Step.ConfigHeader {
    return b.addConfigHeader(.{
        .style = .{ .cmake = upstream.path("src/jversion.h.in") },
        .include_path = "jversion.h",
    }, .{ .COPYRIGHT_YEAR = "1991-2025" });
}

fn generateWrapper(wf: *std.Build.Step.WriteFile, base_name: []const u8, bits: u8) []const u8 {
    const filename = std.fmt.allocPrint(wf.step.owner.allocator, "{s}-{d}.c", .{ base_name, bits }) catch unreachable;
    const content = std.fmt.allocPrint(wf.step.owner.allocator,
        \\#define BITS_IN_JSAMPLE {d}
        \\#include "{s}.c"
        \\
    , .{ bits, base_name }) catch unreachable;
    _ = wf.add(filename, content);
    return filename;
}

fn generateWrapperSources(
    wf: *std.Build.Step.WriteFile,
    allocator: std.mem.Allocator,
    bases: []const []const u8,
    bits: u8,
) []const []const u8 {
    const sources = allocator.alloc([]const u8, bases.len) catch @panic("OOM");
    for (bases, 0..) |base, i| {
        sources[i] = generateWrapper(wf, base, bits);
    }
    return sources;
}

fn parseWrapperSpec(spec: []const u8) struct { base: []const u8, bits: u8 } {
    var iter = std.mem.splitBackwardsScalar(u8, spec, '-');
    const bits_str = iter.first();
    const base = iter.rest();
    return .{
        .base = base,
        .bits = std.fmt.parseInt(u8, bits_str, 10) catch 8,
    };
}

fn createBaseFlags(b: *std.Build, platform: zbh.Platform) []const []const u8 {
    var flags = zbh.Flags.Builder.init(b.allocator);
    flags.appendSlice(&.{ "-DBITS_IN_JSAMPLE=8", "-w" });
    flags.appendIf(platform.is_windows, "-D_CRT_SECURE_NO_WARNINGS");
    return flags.items();
}

fn createToolFlags(b: *std.Build, base_flags: []const []const u8, platform: zbh.Platform) []const []const u8 {
    var flags = zbh.Flags.Builder.init(b.allocator);
    flags.appendSlice(base_flags);
    flags.appendSlice(&.{ "-DBMP_SUPPORTED", "-DGIF_SUPPORTED", "-DPPM_SUPPORTED", "-DTARGA_SUPPORTED" });
    flags.appendIf(platform.is_windows, "-DUSE_SETMODE");
    return flags.items();
}

fn createTjFlags(b: *std.Build, base_flags: []const []const u8) []const []const u8 {
    var flags = zbh.Flags.Builder.init(b.allocator);
    flags.appendSlice(base_flags);
    flags.appendSlice(&.{ "-DBMP_SUPPORTED", "-DPPM_SUPPORTED" });
    return flags.items();
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const platform = zbh.Platform.detect(target.result);
    const upstream = b.dependency("upstream", .{});

    // Build options
    const with_simd = b.option(bool, "simd", "Enable SIMD extensions (default: false)") orelse false;
    const with_arith_enc = b.option(bool, "arith-enc", "Include arithmetic encoding support") orelse true;
    const with_arith_dec = b.option(bool, "arith-dec", "Include arithmetic decoding support") orelse true;
    const with_turbojpeg = b.option(bool, "turbojpeg", "Build TurboJPEG API library") orelse true;
    const shared = b.option(bool, "shared", "Build shared libraries instead of static (default: false)") orelse false;

    if (with_simd) {
        @panic("-Dsimd=true is not implemented in this Zig build yet. Use -Dsimd=false.");
    }

    // Config headers
    const arith_enc_val = zbh.Config.boolToOptInt(with_arith_enc);
    const arith_dec_val = zbh.Config.boolToOptInt(with_arith_dec);
    const jconfig_h = createJconfigH(b, upstream, arith_enc_val, arith_dec_val);
    const jconfigint_h = createJconfigintH(b, upstream, platform, target.result.ptrBitWidth(), arith_enc_val, arith_dec_val);
    const jversion_h = createJversionH(b, upstream);

    // Generate wrapper files
    const wrappers = b.addWriteFiles();
    const base_flags = createBaseFlags(b, platform);

    const wrapper_8_sources = generateWrapperSources(wrappers, b.allocator, wrapper_8_bases, 8);
    const wrapper_12_sources = generateWrapperSources(wrappers, b.allocator, wrapper_12_bases, 12);
    const wrapper_16_sources = generateWrapperSources(wrappers, b.allocator, wrapper_16_bases, 16);

    // Build libjpeg
    const jpeg = b.addLibrary(.{
        .name = "jpeg",
        .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }),
        .linkage = if (shared) .dynamic else .static,
    });

    jpeg.addConfigHeader(jconfig_h);
    jpeg.addConfigHeader(jconfigint_h);
    jpeg.addConfigHeader(jversion_h);
    jpeg.addIncludePath(upstream.path("src"));

    jpeg.addCSourceFiles(.{ .root = upstream.path("src"), .files = jpeg_sources, .flags = base_flags });
    jpeg.addCSourceFiles(.{ .root = wrappers.getDirectory(), .files = wrapper_8_sources, .flags = base_flags });
    jpeg.addCSourceFiles(.{ .root = wrappers.getDirectory(), .files = wrapper_12_sources, .flags = base_flags });
    jpeg.addCSourceFiles(.{ .root = wrappers.getDirectory(), .files = wrapper_16_sources, .flags = base_flags });

    if (with_arith_enc or with_arith_dec) {
        jpeg.addCSourceFiles(.{ .root = upstream.path("src"), .files = arith_sources, .flags = base_flags });
    }
    if (with_arith_enc) {
        jpeg.addCSourceFiles(.{ .root = upstream.path("src"), .files = arith_enc_sources, .flags = base_flags });
    }
    if (with_arith_dec) {
        jpeg.addCSourceFiles(.{ .root = upstream.path("src"), .files = arith_dec_sources, .flags = base_flags });
    }

    b.installArtifact(jpeg);
    jpeg.installHeader(upstream.path("src/jpeglib.h"), "jpeglib.h");
    jpeg.installHeader(upstream.path("src/jmorecfg.h"), "jmorecfg.h");
    jpeg.installHeader(upstream.path("src/jerror.h"), "jerror.h");
    jpeg.installConfigHeader(jconfig_h);

    // Build TurboJPEG
    if (with_turbojpeg) {
        const tj_flags = createTjFlags(b, base_flags);
        const tj_ppm_wrappers = &[_][]const u8{
            generateWrapper(wrappers, "rdppm", 8),
            generateWrapper(wrappers, "rdppm", 12),
            generateWrapper(wrappers, "rdppm", 16),
            generateWrapper(wrappers, "wrppm", 8),
            generateWrapper(wrappers, "wrppm", 12),
            generateWrapper(wrappers, "wrppm", 16),
        };

        const turbojpeg = b.addLibrary(.{
            .name = "turbojpeg",
            .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }),
            .linkage = if (shared) .dynamic else .static,
        });

        turbojpeg.addConfigHeader(jconfig_h);
        turbojpeg.addConfigHeader(jconfigint_h);
        turbojpeg.addConfigHeader(jversion_h);
        turbojpeg.addIncludePath(upstream.path("src"));

        turbojpeg.addCSourceFiles(.{ .root = upstream.path("src"), .files = jpeg_sources, .flags = tj_flags });
        turbojpeg.addCSourceFiles(.{ .root = wrappers.getDirectory(), .files = wrapper_8_sources, .flags = tj_flags });
        turbojpeg.addCSourceFiles(.{ .root = wrappers.getDirectory(), .files = wrapper_12_sources, .flags = tj_flags });
        turbojpeg.addCSourceFiles(.{ .root = wrappers.getDirectory(), .files = wrapper_16_sources, .flags = tj_flags });
        turbojpeg.addCSourceFiles(.{ .root = upstream.path("src"), .files = turbojpeg_sources, .flags = tj_flags });
        turbojpeg.addCSourceFiles(.{ .root = wrappers.getDirectory(), .files = tj_ppm_wrappers, .flags = tj_flags });

        if (with_arith_enc or with_arith_dec) {
            turbojpeg.addCSourceFiles(.{ .root = upstream.path("src"), .files = arith_sources, .flags = tj_flags });
        }
        if (with_arith_enc) {
            turbojpeg.addCSourceFiles(.{ .root = upstream.path("src"), .files = arith_enc_sources, .flags = tj_flags });
        }
        if (with_arith_dec) {
            turbojpeg.addCSourceFiles(.{ .root = upstream.path("src"), .files = arith_dec_sources, .flags = tj_flags });
        }

        b.installArtifact(turbojpeg);
        turbojpeg.installHeader(upstream.path("src/turbojpeg.h"), "turbojpeg.h");

        const tjbench = b.addExecutable(.{
            .name = "tjbench",
            .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }),
        });
        tjbench.addConfigHeader(jconfig_h);
        tjbench.addConfigHeader(jconfigint_h);
        tjbench.addConfigHeader(jversion_h);
        tjbench.addIncludePath(upstream.path("src"));
        tjbench.addCSourceFiles(.{ .root = upstream.path("src"), .files = &.{ "tjbench.c", "tjutil.c" }, .flags = tj_flags });
        tjbench.linkLibrary(turbojpeg);
        if (!platform.is_windows) tjbench.linkSystemLibrary("m");
        b.installArtifact(tjbench);

        const tjunittest = b.addExecutable(.{
            .name = "tjunittest",
            .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }),
        });
        tjunittest.addConfigHeader(jconfig_h);
        tjunittest.addConfigHeader(jconfigint_h);
        tjunittest.addConfigHeader(jversion_h);
        tjunittest.addIncludePath(upstream.path("src"));
        tjunittest.addCSourceFiles(.{
            .root = upstream.path("src"),
            .files = &.{ "tjunittest.c", "tjutil.c", "md5/md5.c", "md5/md5hl.c" },
            .flags = tj_flags,
        });
        tjunittest.linkLibrary(turbojpeg);
        b.installArtifact(tjunittest);

        const tjcomp = b.addExecutable(.{
            .name = "tjcomp",
            .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }),
        });
        tjcomp.addConfigHeader(jconfig_h);
        tjcomp.addConfigHeader(jconfigint_h);
        tjcomp.addConfigHeader(jversion_h);
        tjcomp.addIncludePath(upstream.path("src"));
        tjcomp.addCSourceFile(.{ .file = upstream.path("src/tjcomp.c"), .flags = tj_flags });
        tjcomp.linkLibrary(turbojpeg);
        b.installArtifact(tjcomp);

        const tjdecomp = b.addExecutable(.{
            .name = "tjdecomp",
            .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }),
        });
        tjdecomp.addConfigHeader(jconfig_h);
        tjdecomp.addConfigHeader(jconfigint_h);
        tjdecomp.addConfigHeader(jversion_h);
        tjdecomp.addIncludePath(upstream.path("src"));
        tjdecomp.addCSourceFile(.{ .file = upstream.path("src/tjdecomp.c"), .flags = tj_flags });
        tjdecomp.linkLibrary(turbojpeg);
        b.installArtifact(tjdecomp);

        const tjtran = b.addExecutable(.{
            .name = "tjtran",
            .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }),
        });
        tjtran.addConfigHeader(jconfig_h);
        tjtran.addConfigHeader(jconfigint_h);
        tjtran.addConfigHeader(jversion_h);
        tjtran.addIncludePath(upstream.path("src"));
        tjtran.addCSourceFile(.{ .file = upstream.path("src/tjtran.c"), .flags = tj_flags });
        tjtran.linkLibrary(turbojpeg);
        b.installArtifact(tjtran);
    }

    // Build tools
    const tool_flags = createToolFlags(b, base_flags, platform);

    for (tools) |tool| {
        const exe = b.addExecutable(.{
            .name = tool.name,
            .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }),
        });
        exe.addConfigHeader(jconfig_h);
        exe.addConfigHeader(jconfigint_h);
        exe.addConfigHeader(jversion_h);
        exe.addIncludePath(upstream.path("src"));
        exe.addCSourceFiles(.{ .root = upstream.path("src"), .files = tool.sources, .flags = tool_flags });

        if (tool.wrapper_specs.len > 0) {
            var wrapper_paths = b.allocator.alloc([]const u8, tool.wrapper_specs.len) catch @panic("OOM");
            for (tool.wrapper_specs, 0..) |spec, i| {
                const parsed = parseWrapperSpec(spec);
                wrapper_paths[i] = generateWrapper(wrappers, parsed.base, parsed.bits);
            }
            exe.addCSourceFiles(.{ .root = wrappers.getDirectory(), .files = wrapper_paths, .flags = tool_flags });
        }

        exe.linkLibrary(jpeg);
        if (tool.link_math and !platform.is_windows) {
            exe.linkSystemLibrary("m");
        }
        b.installArtifact(exe);
    }

    // CI step
    const ci_step = b.step("ci", "Build release archives for all targets");
    try addCiTargets(b, ci_step);
}

fn addCiTargets(b: *std.Build, ci_step: *std.Build.Step) !void {
    const ci_version = zbh.Dependencies.extractVersionFromUrl(build_zon.dependencies.upstream.url) orelse build_zon.version;

    const write_version = b.addWriteFiles();
    _ = write_version.add("version", ci_version);
    ci_step.dependOn(&b.addInstallFile(write_version.getDirectory().path(b, "version"), "version").step);

    const install_path = b.getInstallPath(.prefix, ".");

    for (zbh.Ci.standard) |target_str| {
        const target = zbh.Ci.resolve(b, target_str);
        const ci_platform = zbh.Platform.detect(target.result);
        const upstream = b.dependency("upstream", .{});

        // Config headers (full arith support for CI)
        const jconfig_h = createJconfigH(b, upstream, 1, 1);
        const jconfigint_h = createJconfigintH(b, upstream, ci_platform, target.result.ptrBitWidth(), 1, 1);
        const jversion_h = createJversionH(b, upstream);

        // Wrappers
        const wrappers = b.addWriteFiles();
        const base_flags = createBaseFlags(b, ci_platform);

        const wrapper_8_sources = generateWrapperSources(wrappers, b.allocator, wrapper_8_bases, 8);
        const wrapper_12_sources = generateWrapperSources(wrappers, b.allocator, wrapper_12_bases, 12);
        const wrapper_16_sources = generateWrapperSources(wrappers, b.allocator, wrapper_16_bases, 16);

        // Build libjpeg
        const jpeg = b.addLibrary(.{
            .name = "jpeg",
            .root_module = b.createModule(.{ .target = target, .optimize = .ReleaseFast, .link_libc = true }),
            .linkage = .static,
        });

        jpeg.addConfigHeader(jconfig_h);
        jpeg.addConfigHeader(jconfigint_h);
        jpeg.addConfigHeader(jversion_h);
        jpeg.addIncludePath(upstream.path("src"));
        jpeg.addCSourceFiles(.{ .root = upstream.path("src"), .files = jpeg_sources, .flags = base_flags });
        jpeg.addCSourceFiles(.{ .root = wrappers.getDirectory(), .files = wrapper_8_sources, .flags = base_flags });
        jpeg.addCSourceFiles(.{ .root = wrappers.getDirectory(), .files = wrapper_12_sources, .flags = base_flags });
        jpeg.addCSourceFiles(.{ .root = wrappers.getDirectory(), .files = wrapper_16_sources, .flags = base_flags });
        jpeg.addCSourceFiles(.{ .root = upstream.path("src"), .files = arith_sources, .flags = base_flags });
        jpeg.addCSourceFiles(.{ .root = upstream.path("src"), .files = arith_enc_sources, .flags = base_flags });
        jpeg.addCSourceFiles(.{ .root = upstream.path("src"), .files = arith_dec_sources, .flags = base_flags });

        // Build TurboJPEG
        const tj_flags = createTjFlags(b, base_flags);
        const tj_ppm_wrappers = &[_][]const u8{
            generateWrapper(wrappers, "rdppm", 8),
            generateWrapper(wrappers, "rdppm", 12),
            generateWrapper(wrappers, "rdppm", 16),
            generateWrapper(wrappers, "wrppm", 8),
            generateWrapper(wrappers, "wrppm", 12),
            generateWrapper(wrappers, "wrppm", 16),
        };

        const turbojpeg = b.addLibrary(.{
            .name = "turbojpeg",
            .root_module = b.createModule(.{ .target = target, .optimize = .ReleaseFast, .link_libc = true }),
            .linkage = .static,
        });

        turbojpeg.addConfigHeader(jconfig_h);
        turbojpeg.addConfigHeader(jconfigint_h);
        turbojpeg.addConfigHeader(jversion_h);
        turbojpeg.addIncludePath(upstream.path("src"));
        turbojpeg.addCSourceFiles(.{ .root = upstream.path("src"), .files = jpeg_sources, .flags = tj_flags });
        turbojpeg.addCSourceFiles(.{ .root = wrappers.getDirectory(), .files = wrapper_8_sources, .flags = tj_flags });
        turbojpeg.addCSourceFiles(.{ .root = wrappers.getDirectory(), .files = wrapper_12_sources, .flags = tj_flags });
        turbojpeg.addCSourceFiles(.{ .root = wrappers.getDirectory(), .files = wrapper_16_sources, .flags = tj_flags });
        turbojpeg.addCSourceFiles(.{ .root = upstream.path("src"), .files = turbojpeg_sources, .flags = tj_flags });
        turbojpeg.addCSourceFiles(.{ .root = wrappers.getDirectory(), .files = tj_ppm_wrappers, .flags = tj_flags });
        turbojpeg.addCSourceFiles(.{ .root = upstream.path("src"), .files = arith_sources, .flags = tj_flags });
        turbojpeg.addCSourceFiles(.{ .root = upstream.path("src"), .files = arith_enc_sources, .flags = tj_flags });
        turbojpeg.addCSourceFiles(.{ .root = upstream.path("src"), .files = arith_dec_sources, .flags = tj_flags });

        // Build tools
        const tool_flags = createToolFlags(b, base_flags, ci_platform);

        const archive_root = b.fmt("libjpeg-turbo-{s}-{s}", .{ ci_version, target_str });

        const target_lib_dir: std.Build.InstallDir = .{ .custom = b.fmt("{s}/lib", .{archive_root}) };
        const target_bin_dir: std.Build.InstallDir = .{ .custom = b.fmt("{s}/bin", .{archive_root}) };
        const target_include_dir: std.Build.InstallDir = .{ .custom = b.fmt("{s}/include", .{archive_root}) };

        const install_jpeg = b.addInstallArtifact(jpeg, .{ .dest_dir = .{ .override = target_lib_dir } });
        const install_turbojpeg = b.addInstallArtifact(turbojpeg, .{ .dest_dir = .{ .override = target_lib_dir } });

        const install_headers = b.addInstallFileWithDir(upstream.path("src/jpeglib.h"), target_include_dir, "jpeglib.h");
        const install_headers2 = b.addInstallFileWithDir(upstream.path("src/jmorecfg.h"), target_include_dir, "jmorecfg.h");
        const install_headers3 = b.addInstallFileWithDir(upstream.path("src/jerror.h"), target_include_dir, "jerror.h");
        const install_headers4 = b.addInstallFileWithDir(upstream.path("src/turbojpeg.h"), target_include_dir, "turbojpeg.h");
        const install_jconfig = b.addInstallFileWithDir(jconfig_h.getOutput(), target_include_dir, "jconfig.h");

        var tool_installs: [tools.len]*std.Build.Step.InstallArtifact = undefined;
        for (tools, 0..) |tool, i| {
            const exe = b.addExecutable(.{
                .name = tool.name,
                .root_module = b.createModule(.{ .target = target, .optimize = .ReleaseFast, .link_libc = true }),
            });
            exe.addConfigHeader(jconfig_h);
            exe.addConfigHeader(jconfigint_h);
            exe.addConfigHeader(jversion_h);
            exe.addIncludePath(upstream.path("src"));
            exe.addCSourceFiles(.{ .root = upstream.path("src"), .files = tool.sources, .flags = tool_flags });

            if (tool.wrapper_specs.len > 0) {
                var wrapper_paths = try b.allocator.alloc([]const u8, tool.wrapper_specs.len);
                for (tool.wrapper_specs, 0..) |spec, j| {
                    const parsed = parseWrapperSpec(spec);
                    wrapper_paths[j] = generateWrapper(wrappers, parsed.base, parsed.bits);
                }
                exe.addCSourceFiles(.{ .root = wrappers.getDirectory(), .files = wrapper_paths, .flags = tool_flags });
            }

            exe.linkLibrary(jpeg);
            if (tool.link_math and !ci_platform.is_windows) {
                exe.linkSystemLibrary("m");
            }
            tool_installs[i] = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = target_bin_dir } });
        }

        const tjbench = b.addExecutable(.{
            .name = "tjbench",
            .root_module = b.createModule(.{ .target = target, .optimize = .ReleaseFast, .link_libc = true }),
        });
        tjbench.addConfigHeader(jconfig_h);
        tjbench.addConfigHeader(jconfigint_h);
        tjbench.addConfigHeader(jversion_h);
        tjbench.addIncludePath(upstream.path("src"));
        tjbench.addCSourceFiles(.{ .root = upstream.path("src"), .files = &.{ "tjbench.c", "tjutil.c" }, .flags = tj_flags });
        tjbench.linkLibrary(turbojpeg);
        if (!ci_platform.is_windows) tjbench.linkSystemLibrary("m");
        const install_tjbench = b.addInstallArtifact(tjbench, .{ .dest_dir = .{ .override = target_bin_dir } });

        const tjunittest = b.addExecutable(.{
            .name = "tjunittest",
            .root_module = b.createModule(.{ .target = target, .optimize = .ReleaseFast, .link_libc = true }),
        });
        tjunittest.addConfigHeader(jconfig_h);
        tjunittest.addConfigHeader(jconfigint_h);
        tjunittest.addConfigHeader(jversion_h);
        tjunittest.addIncludePath(upstream.path("src"));
        tjunittest.addCSourceFiles(.{
            .root = upstream.path("src"),
            .files = &.{ "tjunittest.c", "tjutil.c", "md5/md5.c", "md5/md5hl.c" },
            .flags = tj_flags,
        });
        tjunittest.linkLibrary(turbojpeg);
        const install_tjunittest = b.addInstallArtifact(tjunittest, .{ .dest_dir = .{ .override = target_bin_dir } });

        const tjcomp = b.addExecutable(.{
            .name = "tjcomp",
            .root_module = b.createModule(.{ .target = target, .optimize = .ReleaseFast, .link_libc = true }),
        });
        tjcomp.addConfigHeader(jconfig_h);
        tjcomp.addConfigHeader(jconfigint_h);
        tjcomp.addConfigHeader(jversion_h);
        tjcomp.addIncludePath(upstream.path("src"));
        tjcomp.addCSourceFile(.{ .file = upstream.path("src/tjcomp.c"), .flags = tj_flags });
        tjcomp.linkLibrary(turbojpeg);
        const install_tjcomp = b.addInstallArtifact(tjcomp, .{ .dest_dir = .{ .override = target_bin_dir } });

        const tjdecomp = b.addExecutable(.{
            .name = "tjdecomp",
            .root_module = b.createModule(.{ .target = target, .optimize = .ReleaseFast, .link_libc = true }),
        });
        tjdecomp.addConfigHeader(jconfig_h);
        tjdecomp.addConfigHeader(jconfigint_h);
        tjdecomp.addConfigHeader(jversion_h);
        tjdecomp.addIncludePath(upstream.path("src"));
        tjdecomp.addCSourceFile(.{ .file = upstream.path("src/tjdecomp.c"), .flags = tj_flags });
        tjdecomp.linkLibrary(turbojpeg);
        const install_tjdecomp = b.addInstallArtifact(tjdecomp, .{ .dest_dir = .{ .override = target_bin_dir } });

        const tjtran = b.addExecutable(.{
            .name = "tjtran",
            .root_module = b.createModule(.{ .target = target, .optimize = .ReleaseFast, .link_libc = true }),
        });
        tjtran.addConfigHeader(jconfig_h);
        tjtran.addConfigHeader(jconfigint_h);
        tjtran.addConfigHeader(jversion_h);
        tjtran.addIncludePath(upstream.path("src"));
        tjtran.addCSourceFile(.{ .file = upstream.path("src/tjtran.c"), .flags = tj_flags });
        tjtran.linkLibrary(turbojpeg);
        const install_tjtran = b.addInstallArtifact(tjtran, .{ .dest_dir = .{ .override = target_bin_dir } });

        // Create archive
        const archive = zbh.Archive.create(b, archive_root, ci_platform.is_windows, install_path);
        archive.step.dependOn(&install_jpeg.step);
        archive.step.dependOn(&install_turbojpeg.step);
        archive.step.dependOn(&install_headers.step);
        archive.step.dependOn(&install_headers2.step);
        archive.step.dependOn(&install_headers3.step);
        archive.step.dependOn(&install_headers4.step);
        archive.step.dependOn(&install_jconfig.step);
        for (&tool_installs) |tool_install| {
            archive.step.dependOn(&tool_install.step);
        }
        archive.step.dependOn(&install_tjbench.step);
        archive.step.dependOn(&install_tjunittest.step);
        archive.step.dependOn(&install_tjcomp.step);
        archive.step.dependOn(&install_tjdecomp.step);
        archive.step.dependOn(&install_tjtran.step);
        ci_step.dependOn(&archive.step);
    }
}

fn parseVersion(ver: []const u8) struct { major: u32, minor: u32, patch: u32 } {
    var parts: [3]u32 = .{ 0, 0, 0 };
    var iter = std.mem.splitScalar(u8, ver, '.');
    var i: usize = 0;
    while (iter.next()) |part| : (i += 1) {
        if (i >= 3) break;
        parts[i] = std.fmt.parseInt(u32, part, 10) catch 0;
    }
    return .{ .major = parts[0], .minor = parts[1], .patch = parts[2] };
}
