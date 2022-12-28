# `cfn` - C functions in Fennel

Experimental macro-library that translates special S-expressions to C, compiles the resulting code and loads it via LuaJIT's FFI library.

## Usage and examples

Import the only macro this library provides:

```fennel
(import-macros {: cfn} :cfn)
```

Now functions can be defined like this:

```fennel
>> (cfn vaiv :int [:int a :int b]
     (return (+ a b)))
nil
>> (vaiv 1 2)
3
```

Redefinition is supported in the REPL:

```fennel
>> (cfn vaiv :int [:int a :int b]
     (return (+ a b)))
nil
>> (vaiv 1 2)
3
>> (cfn vaiv :int [:int a :int b :int c]
     (return (- (+ a b) c)))
nil
>> (vaiv 1 2 3)
0
```

Automatic imports:

```fennel
(cfn fact "unsigned long long" [:int a]
   (local "unsigned long long" res 1)
   (for [:int i 1 (<= i a) (++ i)]
     (stdio/printf "%d\n" i)
     (set res (* res i)))
   (return res))
 (fib 11)
```

In this example, `stdio/printf` automatically generates `#include <stdio.h>` before the function definition.

Recursion:

```fennel
(cfn fib :int [:int a]
  (if (<= a 0)
      (return 0)
      (== a 1)
      (return 1)
      (do (local :int x (fib (- a 1)))
          (local :int y (fib (- a 2)))
          (return (+ x y)))))
```

## Limitations

This project is mostly experimental and in the early stages of development.
Code may lead to unexpected crashes.

Not all of the C syntax is supported by the parser.

## License

MIT License

Copyright (c) 2022 Andrey Listopadov
