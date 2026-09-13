//! Sample Vey extension. It receives the launcher input, shouts it back, and asks the host to
//! copy it. It can do nothing else: the only functions it can call are the two imports below,
//! and the host only wires an import if the manifest declares the capability.

#[link(wasm_import_module = "vey")]
extern "C" {
    fn log(ptr: *const u8, len: usize);
    fn clipboard_write(ptr: *const u8, len: usize);
}

/// Host calls this to reserve space, then writes the input string into it.
#[no_mangle]
pub extern "C" fn alloc(len: usize) -> *mut u8 {
    let mut buf = Vec::with_capacity(len.max(1));
    let ptr = buf.as_mut_ptr();
    std::mem::forget(buf);
    ptr
}

/// Entry point: (input ptr, input len) -> pointer to a (len: u32 little-endian, bytes...) result record.
#[no_mangle]
pub extern "C" fn run(ptr: *const u8, len: usize) -> *const u8 {
    let input = unsafe { std::str::from_utf8_unchecked(std::slice::from_raw_parts(ptr, len)) };
    let shouted = format!("{}!", input.trim().to_uppercase());
    unsafe {
        log(shouted.as_ptr(), shouted.len());
        clipboard_write(shouted.as_ptr(), shouted.len());
    }
    let mut record = Vec::with_capacity(4 + shouted.len());
    record.extend_from_slice(&(shouted.len() as u32).to_le_bytes());
    record.extend_from_slice(shouted.as_bytes());
    let leaked: &'static mut [u8] = Box::leak(record.into_boxed_slice());
    leaked.as_ptr()
}
