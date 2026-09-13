//! Misbehaving extension used to test the host watchdog: run() never returns.
//! black_box keeps the compiler from proving the loop finite and deleting it.
#[no_mangle]
pub extern "C" fn alloc(len: usize) -> *mut u8 {
    let mut buf = Vec::with_capacity(len.max(1));
    let ptr = buf.as_mut_ptr();
    std::mem::forget(buf);
    ptr
}

#[no_mangle]
pub extern "C" fn run(_ptr: *const u8, _len: usize) -> *const u8 {
    let mut x: u64 = 0;
    loop {
        x = std::hint::black_box(x.wrapping_add(1));
        if std::hint::black_box(false) { break; }
    }
    let _ = x;
    std::ptr::null()
}
