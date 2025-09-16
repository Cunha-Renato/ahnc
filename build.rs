fn main() {
    cfg_aliases::cfg_aliases! {
        win: { target_os = "windows" },
        andr: { target_os = "android" }
    }
}