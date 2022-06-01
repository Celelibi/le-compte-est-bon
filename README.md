# Le Compte est Bon
## Usage
### Pure Python version
There are two version, the pure python version and the Cython version.
To run the python version, use:

    ./numbers.py

It will display the numbers choosen and the target total. Or provide the total
and the random numbers.

    ./numbers.py 123 1 2 3 4 25

### Cython version
To use the cython version you need to have cython installed, obviously. Compile
it with the command `make`. Compilation might take some time as it uses the
[profile guided
optimization](https://en.wikipedia.org/wiki/Profile-guided_optimization) in
gcc. Which means that it compiles it a first time with some instrumentations,
	then run it to gather some statistics, then compile it again using the
	gathered statistics to optimize further the final program.

Then run it in a similar way as a pure python version.

    ./numbers
    ./numbers 123 1 2 3 4 25

It should however be several orders of magnitudes faster than the python
version.

## Game
**Le Compte est Bon** (*The Count is Right*) is a french TV game adapted in many
english-speaking countries with the name *countdown*. It opposes two (or more)
people who try to combine given numbers using the basic arithmetic operators
to reach a given goal.

In the non-computerized version, there are two tiles for each numbers 1 to 10,
and one for each number : 25, 50, 75 and 100. 6 of those tiles are drawn
randomly. A goal number between 101 and 999 (inclusive) is choosen too.

The candidates must combine some (or all) of the given numbers using the 4 basic
operators (+, -, ×, ÷) to reach the given goal. If they can't reach the goal
(which is not always possible), they must produce a total that's the closest
possible to the goal. The intermediate calculations must always be positive
integers. Negative and non-integer results are not allowed.

## How it works
### Overview
Basically, the solver enumerates all the arithmetic operations involving some of
the 6 numbers. Doing so efficiently might not be obvious. Enumerating all the
strings of symbols including the operators and parentheses would yield great
many invalid expressions. Arguably the most efficient way to do this is to use
the [reverse polish
notation](https://en.wikipedia.org/wiki/Reverse_Polish_notation) (RPN). Using
the RPN means only a single string of symbols has to be enumerated. And since
all 4 operators take two operands it is easy to count the number of operands
and operators to determine if appending an operator would yield a valid
expression.

An RPN expression can easily be turned into a infix expression (an expression
with the operators between its operands). Evaluating an RPN expression is easy
too, but evaluating the whole expressions each time it's a complete expression
would recompute some parts of the expressions over and over again. Fortunately,
it's easy to evaluate the RPN expressions progressively: each time an operator
is appended, it's evaluated.

Therefore, the solver works by building two RPN stacks. One with operators, the
full RPN expression. One that's eagerly evaluated. The evaluated RPN doesn't
contain any operator, it is basically a stack of integers. This not only reduces
the amount of computations, it also simplify some conditions on the expression.

It's for example much easier to test if the RPN stack is a completely valid
expression by testing if the evaluated stack contains only a single element.
It's also easier to test if an operator can be appended to the RPN stack by
testing if the evaluated stack contains at least two elements.


### Pruning equivalent expressions
Pruning expressions that generate an intermediate **negative** value is easy.
With the evaluated RPN stack, the solver tests whether subtracting the two
operands would yield a strictly positive value or not. Generating 0 values is
useless, therefore it is prune too.

The division is the only operator that can produce non-integer result. Which is
not allowed. The evaluated RPN allows to test the **divisibility** of the last
two elements on the stack.

**Associative** operators (like + and ×) mean that `a × b = b × a`. Therefore
there's no need to test both. In order to prune some of those, we can use the
evaluated RPN to only the cases where `a >= b`. Thus leaving only the cases
where `a = b` tested twice.

In a similar way, a **commutative** operator (like + and ×) means that `(a + b) + c = a + (b + c)`.
In this case, we can choose to only test left associativity by using the full
RPN stack (with the operators) to not append the `+` operator when the left
operand would be a `+` too.


### Closest number
The function enumerating the expressions prints the expressions that evaluate to
the target value. It also returns the absolute difference between the target
value and the closest value it has generated. This means that when the target
value can be reached, it returns 0. If not, it returns the difference between
the target value and the closest it generated.

This allows the main function to call the enumerating function again. Once with
the taget value minus the difference, once with the target value plus the
difference. That way the program prints all the expressions that are the
closest to the actual target value.
