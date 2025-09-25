# android-ndk
Custom Android NDK builds for different architectures

Google already provides prebuilt Android NDK packages for **Linux x86_64**, so there is no need to rebuild the entire NDK from scratch.  
Instead, this project clones:
```
https://android.googlesource.com/toolchain/llvm-project
```
Builds LLVM/Clang, and replaces the binaries inside the official Google Android NDK with the newly built ones.
By this we get a working android ndk for different arch 
