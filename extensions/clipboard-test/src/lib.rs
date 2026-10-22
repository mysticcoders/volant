//! Volant Clipboard Test: an owner-verification fixture for the ABI 1 `clipboard.write` capability.
//! It copies one line of fictional text and says what it copied. The `v2` feature changes the
//! text, so the same manifest ID gets new code and must be approved again.
#[link(wasm_import_module = "volant")]
extern "C" {
    fn clipboard_write(ptr: *const u8, len: usize);
}

#[cfg(not(feature = "v2"))]
const LABEL: &str = "Volant clipboard test v1";
#[cfg(feature = "v2")]
const LABEL: &str = "Volant clipboard test v2";

#[no_mangle]
pub extern "C" fn alloc(len: usize) -> *mut u8 {
    let mut input = vec![0u8; len.max(1)].into_boxed_slice();
    let ptr = input.as_mut_ptr();
    std::mem::forget(input);
    ptr
}

/// Copies the label, plus the input when there is any, and returns the copied text.
#[no_mangle]
pub extern "C" fn run(ptr: *const u8, len: usize) -> *const u8 {
    let input = unsafe { std::slice::from_raw_parts(ptr, len) };
    let note = std::str::from_utf8(input).unwrap_or("").trim();
    let copied = if note.is_empty() { LABEL.to_string() } else { format!("{LABEL}: {note}") };
    unsafe { clipboard_write(copied.as_ptr(), copied.len()) };
    let output = format!("Copied “{copied}”");
    let mut record = Vec::with_capacity(4 + output.len());
    record.extend_from_slice(&(output.len() as u32).to_le_bytes());
    record.extend_from_slice(output.as_bytes());
    Box::leak(record.into_boxed_slice()).as_ptr()
}
