pub mod error {
    use thiserror::*;
    
    #[cfg(win)]
    pub type ComError = crate::win::error::WinError;
}

pub type ComResult<T> = Result<T, error::ComError>;

pub struct Node {
    publisher: ComPublisher,
    socket: Option<Socket>,
}
impl Node {
    #[inline(always)]
    fn start(&self) -> ComResult<()> {
        self.publisher.start()
    }
}

#[cfg(win)]
pub type ComPublisher = crate::win::WinPublisher;

pub struct Socket;

pub trait Publisher {
    type Error: std::error::Error;

    fn start(&self) -> Result<(), Self::Error>;
    fn stop(&self) -> Result<(), Self::Error>;
}