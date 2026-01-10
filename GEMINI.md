# Odin Language Context
Read `@external-docs/docs-overview.md` to understand the internals and syntax of the Odin language.

## Summary of Odin Language
Odin is a general-purpose, high-performance programming language designed for modern systems. Key features include:
- **Syntax:** Clean, C-like syntax with Pascal-style variable declarations (`name: type`). Procedures are defined with `proc`.
- **Memory Management:** Manual memory management with no garbage collector. Utilizes an implicit `context` system to pass `allocator`s (e.g., `context.allocator`, `context.temp_allocator`) and loggers through the call stack.
- **Type System:** Strong, distinct typing. Supports:
    - **Basic Types:** `int`, `float`, `bool`, `rune`, `string`.
    - **Aggregate Types:** `struct`, `union` (tagged), `enum`.
    - **Collections:** Fixed arrays (`[N]T`), Slices (`[]T`), Dynamic arrays (`[dynamic]T`), Maps (`map[K]V`).
    - **Math Types:** Built-in `matrix` and quaternion types.
- **Data-Oriented Features:** Native support for Structure of Arrays (SOA) with `#soa` slices and `soa_zip`.
- **Control Flow:** `for` loops (C-style and range-based), `switch` (no implicit fallthrough), `defer` for resource cleanup, and `when` for compile-time conditional compilation.
- **Polymorphism:** Parametric polymorphism (generics) for procedures and structs. Subtype polymorphism emulated via the `using` keyword.
- **Interoperability:** Robust `foreign` system for easy interfacing with C libraries (defaulting to `cdecl`).
- **Metaprogramming:** extensive use of Attributes (`@(...)`) and Directives (`#...`) for compiler control and reflection-like capabilities (`typeid`, `any`).

## Project Goal: Dune II Clone
We are going to create our own implementation of a game similar to the RTS classic Dune II.
Features to be implemented are persisted in `PLAN.md`.
