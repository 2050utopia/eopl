(load-relative "../libs/init.scm")
(load-relative "./base/classes/test.scm")
(load-relative "./base/classes/store.scm")
(load-relative "./base/classes/data-structures.scm")
(load-relative "./base/classes/environments.scm")
(load-relative "./base/classes/lang.scm")
(load-relative "./base/classes/interp.scm")
(load-relative "./base/classes/classes.scm")
(load-relative "./base/classes/class-cases.scm")

;; see new stuff

(define debug? (make-parameter #t))

(define the-lexical-spec
  '((whitespace (whitespace) skip)
    (comment ("%" (arbno (not #\newline))) skip)
    (identifier
     (letter (arbno (or letter digit "_" "-" "?")))
     symbol)
    (number (digit (arbno digit)) number)
    (number ("-" digit (arbno digit)) number)
    ))

(define the-grammar
  '((program ((arbno class-decl) expression) a-program)

    (expression (number) const-exp)
    (expression
     ("-" "(" expression "," expression ")")
     diff-exp)

    (expression
     ("+" "(" expression "," expression ")")
     sum-exp)

    (expression
     ("zero?" "(" expression ")")
     zero?-exp)

    (expression
     ("if" expression "then" expression "else" expression)
     if-exp)

    (expression (identifier) var-exp)

    (expression
     ("let" (arbno identifier "=" expression) "in" expression)
     let-exp)

    (expression
     ("proc" "(" (separated-list identifier ",") ")" expression)
     proc-exp)

    (expression
     ("(" expression (arbno expression) ")")
     call-exp)

    (expression
     ("letrec"
      (arbno identifier "(" (separated-list identifier ",") ")"
	     "=" expression)
      "in" expression)
     letrec-exp)

    (expression
     ("begin" expression (arbno ";" expression) "end")
     begin-exp)

    (expression
     ("set" identifier "=" expression)
     assign-exp)

    (expression
     ("list" "(" (separated-list expression ",") ")" )
     list-exp)

    ;; new productions for oop

    (class-decl
     ("class" identifier
      "extends" identifier
      (arbno "field" identifier)
      (arbno method-decl)
      )
     a-class-decl)

    (method-decl
     ("method" identifier
      "("  (separated-list identifier ",") ")" ; method formals
      expression
      )
     a-method-decl)

    (expression
     ("new" identifier "(" (separated-list expression ",") ")")
     new-object-exp)

    ;; this is special-cased to prevent it from mutation
    (expression
     ("self")
     self-exp)

    (expression
     ("send" expression identifier
      "("  (separated-list expression ",") ")")
     method-call-exp)

    ;;new stuff
    (expression
     ("instanceof" "(" expression "," identifier ")")
     inst-of-exp)

    (expression
     ("super" identifier    "("  (separated-list expression ",") ")")
     super-call-exp)

    ))

  ;;;;;;;;;;;;;;;; sllgen boilerplate ;;;;;;;;;;;;;;;;

(sllgen:make-define-datatypes the-lexical-spec the-grammar)

(define show-the-datatypes
  (lambda () (sllgen:list-define-datatypes the-lexical-spec the-grammar)))

(define scan&parse
  (sllgen:make-string-parser the-lexical-spec the-grammar))

(define just-scan
  (sllgen:make-string-scanner the-lexical-spec the-grammar))




;; value-of : Exp * Env -> ExpVal
(define value-of
  (lambda (exp env)
    (cases expression exp

	   (const-exp (num) (num-val num))

	   (var-exp (var) (deref (apply-env env var)))

	   (diff-exp (exp1 exp2)
		     (let ((val1
			    (expval->num
			     (value-of exp1 env)))
			   (val2
			    (expval->num
			     (value-of exp2 env))))
		       (num-val
			(- val1 val2))))

	   (sum-exp (exp1 exp2)
		    (let ((val1
			   (expval->num
			    (value-of exp1 env)))
			  (val2
			   (expval->num
			    (value-of exp2 env))))
		      (num-val
		       (+ val1 val2))))

	   (zero?-exp (exp1)
		      (let ((val1 (expval->num (value-of exp1 env))))
			(if (zero? val1)
			    (bool-val #t)
			    (bool-val #f))))

	   (if-exp (exp0 exp1 exp2)
		   (if (expval->bool (value-of exp0 env))
		       (value-of exp1 env)
		       (value-of exp2 env)))

	   (let-exp (vars exps body)
		    (if (instrument-let)
			(printf "entering let ~s~%" vars))
		    (let ((new-env
			   (extend-env
			    vars
			    (map newref (values-of-exps exps env))
			    env)))
		      (if (instrument-let)
			  (begin
			    (printf "entering body of let ~s with env =~%" vars)
			    (pretty-print (env->list new-env))
			    (printf "store =~%")
			    (pretty-print (store->readable (get-store-as-list)))
			    (printf "~%")
			    ))
		      (value-of body new-env)))

	   (proc-exp (bvars body)
		     (proc-val
		      (procedure bvars body env)))

	   (call-exp (rator rands)
		     (let ((proc (expval->proc (value-of rator env)))
			   (args (values-of-exps rands env)))
		       (apply-procedure proc args)))

	   (letrec-exp (p-names b-varss p-bodies letrec-body)
		       (value-of letrec-body
				 (extend-env-rec** p-names b-varss p-bodies env)))

	   (begin-exp (exp1 exps)
		      (letrec
			  ((value-of-begins
			    (lambda (e1 es)
			      (let ((v1 (value-of e1 env)))
				(if (null? es)
				    v1
				    (value-of-begins (car es) (cdr es)))))))
			(value-of-begins exp1 exps)))

	   (assign-exp (x e)
		       (begin
			 (setref!
			  (apply-env env x)
			  (value-of e env))
			 (num-val 27)))


	   (list-exp (exps)
		     (list-val
		      (values-of-exps exps env)))

	   ;; new cases for CLASSES language

	   (new-object-exp (class-name rands)
			   (let ((args (values-of-exps rands env))
				 (obj (new-object class-name)))
			     (apply-method
			      (find-method class-name 'initialize)
			      obj
			      args)
			     obj))

	   (self-exp ()
		     (apply-env env '%self))

	   ;; new stuff
	   (inst-of-exp (exp class-name)
			(let ((obj (value-of exp env)))
			  (if (eq? (object->class-name obj) class-name)
			      (bool-val #t)
			      (bool-val #f))))


	   (method-call-exp (obj-exp method-name rands)
			    (let ((args (values-of-exps rands env))
				  (obj (value-of obj-exp env)))
			      (apply-method
			       (find-method (object->class-name obj) method-name)
			       obj
			       args)))

	   (super-call-exp (method-name rands)
			   (let ((args (values-of-exps rands env))
				 (obj (apply-env env '%self)))
			     (apply-method
			      (find-method (apply-env env '%super) method-name)
			      obj
			      args)))
	   )))


(run "class aclass extends object
       field i
        method initialize(x) set i = x
        method m(y) -(i,-(0,y))

      let o1 = new aclass(3)
       in instanceof(o1, bclass)")
;; => #f

(run "class aclass extends object
       field i
        method initialize(x) set i = x
        method m(y) -(i,-(0,y))

      let o1 = new aclass(3)
       in instanceof(o1, aclass)")

;; => #t
(run-all)
