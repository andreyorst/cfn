(comment
  "MIT License

Copyright (c) 2022 Andrey Listopadov

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the “Software”), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.")

;;; Utils
(local manglings {})

(fn even? [x] (= 0 (% x 2)))
(fn odd? [x] (not (even? x)))
(fn string? [x] (= :string (type x)))
(fn number? [x] (= :number (type x)))
(fn nil? [x] (= nil x))
(fn map [f lst] (icollect [_ v (ipairs lst)] (f v)))
(fn first [[x]] x)
(fn rest [x]
  (if (list? x)
      (list (unpack x 2))
      [(unpack x 2)]))

;;; Arglist

(fn format-arglist [arglist annotation?]
  "Given the arglist with type annotation, format an arglist that is
acceptable by the C compiler.

[:int x :float y :char* s] => (int x, float y, char* s)"
  (let [(ok? arg i)
        (accumulate [(ok? arg n) (values true nil 0)
                     i item (ipairs arglist)
                     &until (not ok?)]
          (values (or (and (odd? i) (string? item))
                      (and (even? i) (sym? item)))
                  item i))]
    (assert-compile ok? (string.format
                         (if (odd? i)
                             "missing a type annotation for arg %s"
                             "missing an argument for type %s")
                         (tostring arg))
                    arg)
    (assert-compile (= 0 (% (length arglist) 2))
                    "extra type annotator at the end of arglist"
                    arglist)
    (.. "("
        (if (and (= 0 (length arglist)) annotation?)
            "void"
            (table.concat
             (fcollect [i 1 (length arglist) 2]
               (if annotation?
                   (. arglist i)
                   (.. (. arglist i) " " (tostring (. arglist (+ 1 i))))))
             ", "))
        ")")))

;;; Expressions

(fn format-return [[_ val] format-expr]
  (string.format "return %s;" (format-expr val)))

(fn format-local [[type-ann name initializer &as expr] format-expr]
  (assert-compile (= 3 (length expr))
                  (match (length expr)
                    1 (if (string? type-ann)
                          "missing local name and initializer"
                          "missing type annotation")
                    2 (if (and (string? type-ann) (sym? type-ann))
                          "missing initializer"
                          (sym? type-ann)
                          "missing type annotation before name"
                          "local must contain type name and initializer")
                    _ "local must contain type name and initializer")
                  expr)
  (assert-compile (string? type-ann) "expected type annotation before name" expr)
  (assert-compile (sym? name) "local name must be a symbol" expr)
  (string.format
   "%s %s = %s;"
   type-ann
   (tostring name)
   (format-expr initializer)))

(fn format-body [body imports format-expr]
  (string.format "{%s}" (table.concat (map #(format-expr $ imports) body) "\n  ")))

(fn format-math [op exprs format-expr]
  (let [op (tostring op)]
    (match op
      (where (or "-" "!" "++" "--") (= 1 (length exprs)))
      (string.format "(%s %s)" op (first exprs))
      (where (or "+" "-" "*"))
      (.. "(" (table.concat exprs (.. " " op " ")) ")")
      (where (or "<" ">" ">=" "<=" "==" "!=")
             (= 2 (length exprs)))
      (.. "(" (table.concat exprs (.. " " op " ")) ")")
      (where (or "^" "/"))
      (faccumulate [res (string.format
                         "(%s %s %s)"
                         (. exprs 1)
                         op
                         (. exprs 2))
                    i 3 (length exprs)]
        (string.format
         "((%s) %s %s)"
         res
         op
         (. exprs i)))
      _ (assert-compile false "incorrect math op usage" op))))

(fn format-for [[_ bind-table & body] imports format-expr]
  (match bind-table
    (where [type-ann name init ?cond ?how]
           (string? type-ann) (sym? name))
    (.. (string.format "for (%s %s = %s; %s; %s) "
                       type-ann name (format-expr init) (format-expr ?cond) (format-expr ?how))
        (format-body body imports format-expr))
    (where [name init ?cond ?how]
           (sym? name))
    (.. (string.format "for (%s = %s; %s; %s) "
                       name (format-expr init) (format-expr ?cond) (format-expr ?how))
        (format-body body imports format-expr))
    _ (let [[name cond how] bind-table]
        (.. (string.format "for (%s; %s; %s) "
                           name (format-expr cond) (format-expr how))
            (format-body body imports format-expr)))))

(fn format-set [[_ name expr] format-expr]
  (string.format "%s = %s;" (tostring name) (format-expr expr)))

(fn split-import-sym [name]
  (if (string.match name "/")
      (string.match name "([%w_]+)/([%w_]+)")
      (values nil name)))

(fn format-call [[callee & args] imports format-expr]
  (let [callee (tostring callee)
        callee (or (. manglings callee) callee)
        (import callee) (split-import-sym (tostring callee))]
    (when import
      (tset imports import true))
    (string.format
     "%s(%s);"
     callee
     (table.concat (map #(format-expr $ imports) args) ", "))))

(fn format-val [val imports]
  (let [(import val) (split-import-sym (tostring val))]
    (when import
      (tset imports import true))
    val))

(fn format-if [[_ & exprs] imports format-expr]
  (if (= 3 (length exprs))
      (string.format "if %s %s  else %s"
                     (format-expr (. exprs 1) imports)
                     (format-expr (. exprs 2) imports)
                     (format-expr (. exprs 3) imports))
      (= 2 (length exprs))
      (string.format "if %s %s"
                     (format-expr (. exprs 1) imports)
                     (format-expr (. exprs 2) imports)
                     (format-expr (. exprs 3) imports))
      (string.format "if %s %s else %s"
                     (format-expr (. exprs 1) imports)
                     (format-expr (. exprs 2) imports)
                     (format-if [:if (unpack exprs 3)] imports format-expr))))

(fn format-expr [expr imports]
  (if (list? expr)
      (match (tostring (first expr))
        (where (or "+" "-" "/" "*" "^" "++" "--"
                   "<" ">" ">=" "<=" "==" "!="))
        (format-math (first expr)
                     (map #(format-expr $ imports) (rest expr))
                     format-expr)
        :return (format-return expr format-expr)
        :local (format-local (rest expr) format-expr)
        :do (format-body (rest expr) imports format-expr)
        :for (format-for expr imports format-expr)
        :if (format-if expr imports format-expr)
        :set (format-set expr format-expr)
        _ (format-call expr imports format-expr))
      (nil? expr) ""
      (string? expr) (view expr {:escape-newlines? true :line-length math.huge})
      (format-val expr imports)))

(fn compile-module [file-name]
  `(os.execute
    ,(string.format "gcc -shared -fPIC -o lib%s.so %s.c"
                    file-name file-name)))

(fn write-c-file [fname declr body]
  `(let [fname# ,(.. fname ".c")]
     (with-open [f# (_G.io.open fname# :w)]
       (match (f#:write ,(let [imports {}
                               body (format-expr body imports)
                               imports (icollect [import (pairs imports)]
                                         (string.format "#include <%s.h>" import))]
                           (_G.string.format "%s\n%s %s" (table.concat imports "\n") declr body)))
         (nil err-msg#) (error err-msg#)))))

(fn format-declaration [ret-type name arglist]
  (string.format "%s %s %s" ret-type name (format-arglist arglist)))

(fn cfn [name ret-type arglist ...]
  (let [mangled (tostring (gensym (.. (. (ast-source name) :filename) "_" (tostring name))))
        declr (format-declaration ret-type mangled arglist)]
    (tset manglings (tostring name) mangled)
    `(local ,name
       (match (pcall require :ffi)
         (true ffi#)
         (do ,(write-c-file mangled declr (list 'do ...))
             (match (do ,(compile-module mangled))
               true (match (pcall ffi#.load ,(string.format "./lib%s.so" mangled))
                      (true udata#)
                      (do (ffi#.cdef ,(.. declr ";"))
                          (_G.os.execute ,(string.format "rm -f ./lib%s.so ./%s.c" mangled mangled))
                          (. udata# ,mangled))
                      (,(sym :_) err-msg3#) (error err-msg3#))
               (,(sym :_) err-msg2#) (error err-msg2#)))
         ,(sym :_) (error "ffi library unavailable")))))

{: cfn}