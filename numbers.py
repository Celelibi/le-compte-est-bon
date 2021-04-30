#!/usr/bin/env python3

import sys
import random
from collections import Counter



def exprstr(stack):
    prio = {'+': 0, '-': 0, '*': 1, '/': 1}
    assoc = {'+': True, '-': False, '*': True, '/': False}
    s = [(str(v), prio.get(v, 2), assoc.get(v, True)) for v in stack]

    i = 2
    while len(s) > 1:
        if s[i][0] in ('+', '*', '-', '/'):
            op, opprio, opassoc = s[i]
            a, aprio, aassoc = s[i-2]
            b, bprio, bassoc = s[i-1]

            if opprio > aprio:
                a = "(%s)" % a
            if opprio > bprio or (opprio == bprio and not opassoc):
                b = "(%s)" % b

            s[i-2] = ("%s %s %s" % (a, op, b), opprio, opassoc)

            s = s[:i-1] + s[i+1:]
            i -= 1
        else:
            i += 1

    return s[0][0]



def solve(total, values, estack, stack):
    bestsolution = float('inf')

    if len(estack) == 1:
        if total == estack[0]:
            print(total, "=", exprstr(stack))
        bestsolution = abs(total - estack[0])

    if len(estack) >= 2:
        b = estack.pop()
        a = estack.pop()

        # Commutating operations are tried only once
        if a <= b:
            # Don't try the right associative formula for the associative operators
            # (a + b) + c will be tried, no need to try a + (b + c) as well.
            # No need to try a + (b - c) either.
            if stack[-1] not in ("+", "-"):
                estack.append(a+b)
                stack.append('+')
                sol = solve(total, values, estack, stack)
                stack.pop()
                estack.pop()
                bestsolution = min(bestsolution, sol)

            # Don't multiply by 1
            if a != 1:
                # Left associativity only
                if stack[-1] not in ("*", "/"):
                    estack.append(a*b)
                    stack.append('*')
                    sol = solve(total, values, estack, stack)
                    stack.pop()
                    estack.pop()
                    bestsolution = min(bestsolution, sol)

        # Only strictly positive integers
        if a > b:
            estack.append(a-b)
            stack.append('-')
            sol = solve(total, values, estack, stack)
            stack.pop()
            estack.pop()
            bestsolution = min(bestsolution, sol)

        # Only integers and don't divide by 1
        if b > 1 and a % b == 0:
            estack.append(a//b)
            stack.append('/')
            sol = solve(total, values, estack, stack)
            stack.pop()
            estack.pop()
            bestsolution = min(bestsolution, sol)

        estack += [a, b]

    for v in values:
        estack.append(v)
        stack.append(v)
        values[v] -= 1
        sol = solve(total, +values, estack, stack)
        values[v] += 1
        stack.pop()
        estack.pop()
        bestsolution = min(bestsolution, sol)

    return bestsolution



def main():
    if len(sys.argv) >= 3:
        total = int(sys.argv[1])
        values = [int(a) for a in sys.argv[2:]]
    else:
        total = random.randint(101, 1000)
        possible_values = list(range(1, 11)) + [25, 50, 75, 100]
        weights = [2] * 10 + [1, 1, 1, 1]
        values = random.choices(possible_values, weights, k=6)
        print("Values:", ", ".join(str(v) for v in values))
        print("Total:", total)

    c = Counter(values)
    diff = solve(total, c, [], [])
    if diff != 0:
        if (total > diff):
            solve(total - diff, c, [], [])
        solve(total + diff, c, [], [])




if __name__ == '__main__':
    main()
