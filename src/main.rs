#[cfg(win)]
mod win;

mod common;

#[tokio::main]
async fn main() {
    #[cfg(win)]
    win::test().await.unwrap();
}
