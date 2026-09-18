//! Volant Hello World: no imports, permissions, network, or clipboard access.
//! ABI 1: UTF-8 input, length-prefixed UTF-8 output in exported linear memory.
#[no_mangle]
pub extern "C" fn alloc(len: usize) -> *mut u8 {
    let mut input = vec![0u8; len.max(1)].into_boxed_slice();
    let ptr = input.as_mut_ptr();
    std::mem::forget(input);
    ptr
}

#[no_mangle]
pub extern "C" fn run(ptr: *const u8, len: usize) -> *const u8 {
    let input = unsafe { std::slice::from_raw_parts(ptr, len) };
    let name = std::str::from_utf8(input).unwrap_or("").trim();
    let output = format!("Hello, {}!", if name.is_empty() { "world" } else { name });
    let mut record = Vec::with_capacity(4 + output.len());
    record.extend_from_slice(&(output.len() as u32).to_le_bytes());
    record.extend_from_slice(output.as_bytes());
    Box::leak(record.into_boxed_slice()).as_ptr()
}
