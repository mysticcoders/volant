//! Fixture list extension for Volant's own runtime checks: no imports and no dependencies. The real
//! readers live in github.com/mysticcoders/volant-extensions.
//!
//! - plan, query "explain": returns one item instead of a fetch, as a module may for a bad query.
//! - plan, any other query: asks for https://fixture.example.com/feed.json.
//! - render: one row saying whether a 200 response arrived and how long the request was.

#[no_mangle]
pub extern "C" fn alloc(len: usize) -> *mut u8 {
    let mut buffer = vec![0u8; len.max(1)].into_boxed_slice();
    let ptr = buffer.as_mut_ptr();
    std::mem::forget(buffer);
    ptr
}

#[no_mangle]
pub extern "C" fn run(ptr: *const u8, len: usize) -> *const u8 {
    let input = std::str::from_utf8(unsafe { std::slice::from_raw_parts(ptr, len) }).unwrap_or("");
    let output = if input.contains(r#""phase":"plan""#) && input.contains(r#""query":"explain""#) {
        r#"{"items":[{"title":"Fixture explains its query"}]}"#.to_string()
    } else if input.contains(r#""phase":"plan""#) {
        r#"{"fetch":["https://fixture.example.com/feed.json"]}"#.to_string()
    } else {
        let state = if input.contains(r#""status":200"#) { "fetched" } else { "nothing fetched" };
        format!(concat!(r#"{{"items":[{{"title":"Fixture {}","subtitle":"{} bytes of request","#,
                        r#""url":"https://fixture.example.com/story","secondaryURL":"https://fixture.example.com/comments","secondaryTitle":"Open Comments"}}]}}"#),
                state, input.len())
    };
    let mut record = Vec::with_capacity(4 + output.len());
    record.extend_from_slice(&(output.len() as u32).to_le_bytes());
    record.extend_from_slice(output.as_bytes());
    Box::leak(record.into_boxed_slice()).as_ptr()
}
