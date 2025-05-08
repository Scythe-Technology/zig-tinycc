const std = @import("std");

pub const TCCSymbolCallbackFunc = ?*const fn (?*anyopaque, [*:0]const u8, ?*const anyopaque) callconv(.C) void;
pub const TCCErrorFunc = ?*const fn (?*anyopaque, [*:0]const u8) callconv(.C) void;

pub extern fn tcc_new() ?*TCCState;
pub extern fn tcc_delete(s: *TCCState) void;
pub extern fn tcc_set_lib_path(s: *TCCState, path: [*:0]const u8) void;
pub extern fn tcc_set_error_func(s: *TCCState, error_opaque: ?*anyopaque, error_func: TCCErrorFunc) void;
pub extern fn tcc_get_error_func(s: *TCCState) TCCErrorFunc;
pub extern fn tcc_get_error_opaque(s: *TCCState) ?*anyopaque;
pub extern fn tcc_set_options(s: *TCCState, str: [*:0]const u8) void;
pub extern fn tcc_add_include_path(s: *TCCState, pathname: [*:0]const u8) c_int;
pub extern fn tcc_add_sysinclude_path(s: *TCCState, pathname: [*:0]const u8) c_int;
pub extern fn tcc_define_symbol(s: *TCCState, sym: [*:0]const u8, value: [*:0]const u8) void;
pub extern fn tcc_undefine_symbol(s: *TCCState, sym: [*:0]const u8) void;
pub extern fn tcc_add_file(s: *TCCState, filename: [*:0]const u8) c_int;
pub extern fn tcc_compile_string(s: *TCCState, buf: [*:0]const u8) c_int;
pub extern fn tcc_set_output_type(s: *TCCState, output_type: c_int) c_int;
pub extern fn tcc_add_library_path(s: *TCCState, pathname: [*:0]const u8) c_int;
pub extern fn tcc_add_library(s: *TCCState, libraryname: [*:0]const u8) c_int;
pub extern fn tcc_add_symbol(s: *TCCState, name: [*:0]const u8, val: *const anyopaque) c_int;
pub extern fn tcc_output_file(s: *TCCState, filename: [*:0]const u8) c_int;
pub extern fn tcc_run(s: *TCCState, argc: c_int, argv: [*c][*c]u8) c_int;
pub extern fn tcc_relocate(s1: *TCCState) c_int;
pub extern fn tcc_get_symbol(s: *TCCState, name: [*:0]const u8) ?*anyopaque;
pub extern fn tcc_list_symbols(s: *TCCState, ctx: ?*anyopaque, symbol_cb: TCCSymbolCallbackFunc) void;

/// create a new TCC compilation context
pub fn new() !*TCCState {
    return tcc_new() orelse error.TCCNewError;
}

const page_size = std.heap.page_size_min;

pub const DynMem = struct {
    allocator: std.mem.Allocator,
    mem: []align(page_size) u8,

    pub fn alloc(allocator: std.mem.Allocator, size: usize) !DynMem {
        const mem = try allocator.alignedAlloc(u8, page_size, size);
        return .{
            .allocator = allocator,
            .mem = mem,
        };
    }

    pub fn free(self: DynMem) void {
        std.posix.mprotect(self.mem, std.posix.PROT.READ | std.posix.PROT.WRITE) catch {};
        self.allocator.free(self.mem);
    }
};

pub const TCCState = opaque {
    /// set CONFIG_TCCDIR at runtime
    pub fn set_lib_path(self: *TCCState, path: [:0]const u8) void {
        tcc_set_lib_path(self, path.ptr);
    }

    /// set error/warning display callback
    pub fn set_error_func(self: *TCCState, error_opaque: ?*anyopaque, error_func: TCCErrorFunc) void {
        tcc_set_error_func(self, error_opaque, error_func);
    }

    /// return error/warning callback
    pub fn get_error_func(self: *TCCState) ?TCCErrorFunc {
        return tcc_get_error_func(self);
    }

    /// return error/warning callback opaque pointer
    pub fn get_error_opaque(self: *TCCState) ?*anyopaque {
        return tcc_get_error_opaque(self);
    }

    /// set options as from command line (multiple supported)
    pub fn set_options(self: *TCCState, str: [:0]const u8) void {
        tcc_set_options(self, str.ptr);
    }

    /// add include path
    pub fn add_include_path(self: *TCCState, pathname: [:0]const u8) void {
        tcc_add_include_path(self, pathname.ptr);
    }

    /// add in system include path
    pub fn add_sysinclude_path(self: *TCCState, pathname: [:0]const u8) void {
        tcc_add_sysinclude_path(self, pathname.ptr);
    }

    /// define preprocessor symbol 'sym'. value can be NULL, sym can be "sym=val"
    pub fn define_symbol(self: *TCCState, sym: [:0]const u8, value: ?[:0]const u8) void {
        tcc_define_symbol(self, sym.ptr, if (value) value.ptr else null);
    }

    /// undefine preprocess symbol 'sym'
    pub fn undefine_symbol(self: *TCCState, sym: [:0]const u8) void {
        tcc_undefine_symbol(self, sym.ptr);
    }

    /// add a file (C file, dll, object, library, ld script)
    pub fn add_file(self: *TCCState, filename: [:0]const u8) !void {
        if (tcc_add_file(self, filename.ptr) == -1)
            return error.AddFileError;
    }

    /// add multiple files (C file, dll, object, library, ld script)
    pub fn add_files(self: *TCCState, filenames: [][:0]const u8) !void {
        for (filenames) |filename|
            try self.add_file(filename.ptr);
    }

    /// compile a string containing a C source
    pub fn compile_string(self: *TCCState, buf: [:0]const u8) !void {
        if (tcc_compile_string(self, buf.ptr) == -1)
            return error.CompileError;
    }

    /// set output type. MUST BE CALLED before any compilation
    pub fn set_output_type(self: *TCCState, output_type: c_int) void {
        _ = tcc_set_output_type(self, output_type);
    }

    /// equivalent to -Lpath option
    pub fn add_library_path(self: *TCCState, pathname: [:0]const u8) void {
        _ = tcc_add_library_path(self, pathname.ptr);
    }

    /// the library name is the same as the argument of the '-l' option
    pub fn add_library(self: *TCCState, library_name: [:0]const u8) !void {
        if (tcc_add_library(self, library_name.ptr) == -1)
            return error.LinkError;
    }

    /// add a symbol to the compiled program
    pub fn add_symbol(self: *TCCState, name: [:0]const u8, val: *const anyopaque) c_int {
        return tcc_add_symbol(self, name.ptr, val);
    }

    /// output an executable, library or object file. DO NOT call
    /// relocate() before.
    pub fn output_file(self: *TCCState, filename: [:0]const u8) !void {
        if (tcc_output_file(self, filename.ptr) == -1)
            return error.OutputFileError;
    }

    /// link and run main() function and return its value. DO NOT call
    /// relocate() before.
    pub fn run(self: *TCCState, args: [][*:0]const u8) c_int {
        return tcc_run(self, @intCast(args.len), args.ptr);
    }

    /// do all relocations (needed before using get_symbol())
    pub fn relocate(self: *TCCState) !void {
        const ret = tcc_relocate(self);
        if (ret == -1)
            return error.RelocateError;
    }

    /// return symbol value or NULL if not found
    pub fn get_symbol(self: *TCCState, name: [:0]const u8) ?*anyopaque {
        return tcc_get_symbol(self, name.ptr);
    }

    /// return symbol value or NULL if not found
    pub fn list_symbols(self: *TCCState, ctx: ?*anyopaque, symbol_cb: TCCSymbolCallbackFunc) void {
        tcc_list_symbols(self, ctx, symbol_cb);
    }

    pub fn compileStringOnce(self: *TCCState, allocator: std.mem.Allocator, buf: []const u8) !void {
        const zbytes = try allocator.dupeZ(u8, buf);
        defer allocator.free(zbytes);
        try self.compile_string(zbytes);
        return try self.relocate();
    }

    /// free a TCC compilation context
    pub fn deinit(self: *TCCState) void {
        tcc_delete(self);
    }
};

pub const TCCRelocation = union(enum) {
    /// Allocate and manage memory internally
    auto,
    /// copy code to memory passed by the caller
    addr: *anyopaque,
};

pub const TCC_OUTPUT_MEMORY: c_int = 1;
pub const TCC_OUTPUT_EXE: c_int = 2;
pub const TCC_OUTPUT_DLL: c_int = 3;
pub const TCC_OUTPUT_OB: c_int = 4;
pub const TCC_OUTPUT_PREPROCESS: c_int = 5;

test "ref all decls" {
    std.testing.refAllDecls(@This());
}

test "tcc - nothing" {
    const tcc = try new();
    defer tcc.deinit();
}

test "tcc - compile" {
    const tcc = try new();
    defer tcc.deinit();

    tcc.set_options("-std=c11 -nostdlib -Wl,--export-all-symbols");
    tcc.set_output_type(TCC_OUTPUT_MEMORY);

    try tcc.compile_string(
        \\int blank() {
        \\  return 123;
        \\}
    );

    try tcc.relocate();

    const Fn = *const fn () callconv(.c) c_int;

    const blank_sym = tcc.get_symbol("blank") orelse return error.SymbolError;

    const res = @call(.auto, @as(Fn, @ptrCast(@alignCast(blank_sym))), .{});

    try std.testing.expectEqual(res, 123);
}

test "tcc - compileStringOnce" {
    const allocator = std.testing.allocator;

    const tcc = try new();
    defer tcc.deinit();

    tcc.set_options("-std=c11 -nostdlib -Wl,--export-all-symbols");
    tcc.set_output_type(TCC_OUTPUT_MEMORY);

    try tcc.compileStringOnce(allocator,
        \\int blank() {
        \\  return 234;
        \\}
    );

    const Fn = *const fn () callconv(.c) c_int;

    const blank_sym = tcc.get_symbol("blank") orelse return error.SymbolError;

    const res = @call(.auto, @as(Fn, @ptrCast(@alignCast(blank_sym))), .{});

    try std.testing.expectEqual(res, 234);
}
