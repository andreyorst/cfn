# `cfn` - C functions in Fennel

Experimental macro-library that translates special S-expressions to C, compiles the resulting code and loads it via LuaJIT's FFI library.

## Usage and examples

Import the only macro this library provides:

```fennel
(import-macros {: cfn} :cfn)
```

Now functions can be defined like this:

```fennel
(cfn vaiv :int [:int a :int b]
   (return (+ a b)))
(vaiv 1 2) ;; => 3
```

### Dynamic redefinition

Redefinition is supported in the REPL:

```fennel
>> (cfn vaiv :int [:int a :int b]
     (return (+ a b)))
nil
>> (vaiv 1 2)
3
>> (local old-vaiv vaiv)
nil
>> (cfn vaiv :int [:int a :int b :int c]
     (return (- (+ a b) c)))
nil
>> (vaiv 1 2 3)
0
>> (old-vaiv 4 5)
9
```

This internally generates functions named `unknown_vaiv_1_` and `unknown_vaiv_2_` which are both loaded, so the old variant still can be called, if it is stored in another variable.
Note, however, that when calling one C function from the other one, the inner calls resolve to the functions that were available when the caller was compiled:



Support for dynamic redefinition requires function names to be heavily mangled, but recursion should still work as expected:

```fennel
(cfn fib :int [:int a]
  (if (<= a 0)
      (return 0)
      (== a 1)
      (return 1)
      (return (+ (fib (- a 1)) (fib (- a 2))))))
```


### Automatic imports

Automatic imports are made when code uses symbols formatted as `foo/bar`, resulting in inclusion of `#include <foo.h>` in the generated code.
In the following example, `stdio/printf` automatically generates `#include <stdio.h>` before the function definition, and `printf` is called in the body:

```fennel
>> (cfn fact "unsigned long long" [:int a]
     (let ["unsigned long long" res 1]
       (for [:int i 1 (<= i a) (++ i)]
         (stdio/printf "%d\n" i)
         (set res (* res i)))
       (return res)))
nil
>> (fib 11)
>> (fact 4)
1
2
3
4
#<24ULL>
```

## Rationale

Lua provides a way of interfacing with C for performance critical parts of the code.
However, in Lua how one would access is a bit clumsy, and LuaJIT includes a more streamlined library for interfacing with C.
So in order to interface with C one just needs their code to be compiled into a shared library, load it, and then declare a function via the `ffi.fdef` call.

In Fennel, a macro can combine both steps into one, so the only requirements for this library to work are being on LuaJIT, and having GCC on the path.
There's still a part, where you have to write C using C syntax.

Thus, this library also includes its own DSL for writing C using S-expressions.
So this is not a lisp that is being compiled to C, it is plain C, just in disguise.

The `cfn` macro parses the body of the function, and generates a string of C code, that is then compiled with GCC via the `os.exec` call.
The result is then loaded via LuaJIT's FFI library and placed in the local variable, named after the function name.
Here's (a bit streamlined) macroexpansion of the `(cfn vaiv :int [:int a :int b] (return (+ a b)))` definition:

```fennel
(local vaiv
  (match (pcall require "ffi")
    (true ffi)
    (let [fname "unknown_vaiv_61_.c"]
      (with-open [f (_G.io.open fname "w")]
        (match (f:write "int unknown_vaiv_61_ (int a, int b) {return (a + b);}")
          (nil err-msg) (error err-msg)))
      (match (_G.os.execute "gcc -shared -fPIC -o libunknown_vaiv_61_.so unknown_vaiv_61_.c")
        true (match (pcall ffi.load "./libunknown_vaiv_61_.so")
               (true udata)
               (do
                 (ffi.cdef "int unknown_vaiv_61_ (int a, int b);")
                 (_G.os.execute "rm -f ./libunknown_vaiv_61_.so ./unknown_vaiv_61_.c")
                 (. udata "unknown_vaiv_61_"))
               (_ err-msg3) (error err-msg3))
        (_ err-msg2) (error err-msg2)))
    _ (error "ffi library unavailable")))
```

This, of course, comes with all danger that C holds in its hands.
No validation of the code is done by the library, as it is just a simple transpiler.

## Limitations

This project is mostly experimental and in the early stages of development.
Code may lead to unexpected crashes.

Not all of the C syntax is supported by the parser.

## License

MIT License

Copyright (c) 2022 Andrey Listopadov
