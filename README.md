nloxvm is a Nim implementation of a bytecode virtual machine for interpreting the Lox programming language. This implementation is based on the clox interpreter, which is done in C.

## What is Lox?
Lox is a scripting language created by Robert Nystrom to teach in a practical way the implementation of a programming language throughout the book Crafting Interpreters. To learn more, visit [craftinginterpreters.com](https://www.craftinginterpreters.com/).

## Why write another Lox VM interpreter?
I have always been interested in learning how a programming language is implemented and the book Crafting Interpreters brings this in a very didactic and practical way. So it's a perfect opportunity to learn something new and develop myself as a programmer.

## Why use the Nim programming language?
Nim is currently the programming language I have the best aptitude for and I feel more comfortable exploring something new and unknown. I tried to keep this Nim implementation as faithful as possible with the base implementation made in C.

### Challenges when using Nim
The big challenge was trying to keep the project organization (files and code) the same as the book, since refactoring/code reallocation was necessary to avoid cyclical imports. To do this, I had to create some `*_helpers.nim` modules, as well as put all type declarations in `types.nim`. I had to bail myself out to `{.exportc.}` and `{.importc.}` to avoid a major code change.

## Progress
I. WELCOME
- [x] 1. Introduction
- [x] 2. A Map of the Territory
- [x] 3. The Lox Language

III. A TREE-WALK INTERPRETER
- [x] 14. Chunks of Bytecode
- [x] 15. A Virtual Machine
- [x] 16. Scanning on Demand
- [x] 17. Compiling Expressions
- [x] 18. Types of Values
- [x] 19. Strings
- [x] 20. Hash Tables
- [x] 21. Global Variables
- [x] 22. Local Variables
- [x] 23. Jumping Back and Forth
- [x] 24. Calls and Functions
- [x] 25. Closures
- [x] 26. Garbage Collection
- [x] 27. Classes and Instances
- [x] 28. Methods and Initializers
- [x] 29. Superclasses
- [x] 30. Optimization

Visit [nlox](https://github.com/rockcavera/nim-nlox) to see the Nim implementation of the jlox-based Lox interpreter.

## How to use nloxvm?
First you need to have a [Nim](https://nim-lang.org/install.html "Nim") 2.0.0 compiler or higher.

Then clone this repository:
```
git clone https://github.com/rockcavera/nim-nloxvm.git
```

Enter the cloned folder:
```
cd nim-nloxvm
```

Finally, compile the project:
```
nim c -d:release src/nloxvm
```

or install with Nimble:
```
nimble install
```

For best performance, I recommend compiling with:
```
nim c -d:danger -d:lto src/nloxvm
```

## How to perform tests?
Assuming you have already cloned the repository, just be in the project folder and type:
```
nim r tests/tall
```

or:
```
nimble test
```

## License
All files are under the MIT license, with the exception of the .lox files located in the tests/scripts folder, which are under this [LICENSE](/tests/scripts/LICENSE) because they are third-party code, which can be accessed [here](https://github.com/munificent/craftinginterpreters/tree/master/test).
