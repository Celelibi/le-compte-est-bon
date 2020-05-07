#!/usr/bin/env python3

import sys
import random
from collections import Counter
from cpython cimport PyObject_Calloc as calloc, PyObject_Free as free
from libc cimport limits, stdio



cdef struct intestack:
    int val
    intestack *nextestack



cdef struct intopstack:
    bint isop
    char op
    int val
    intopstack *nextopstack
    intopstack *end



cdef struct count:
    unsigned char value
    unsigned char count
    count *nextcount



cdef void printexpr(intopstack *stack, int pprio, bint passoc, bint isleft) nogil:
    if not stack.isop:
        stdio.printf("%d", stack.val)
        return

    cdef int opprio
    cdef bint opassoc
    cdef bint needparens

    opprio = 1 if stack.op in (b'+', b'-') else 2
    opassoc = (stack.op in (b'+', b'*'))

    needparens = (opprio < pprio) or (not isleft and opprio == pprio and not passoc)

    if needparens:
        stdio.printf("(")

    printexpr(stack.nextopstack.end, opprio, opassoc, True)
    stdio.printf(" %c ", stack.op)
    printexpr(stack.nextopstack, opprio, opassoc, False)

    if needparens:
        stdio.printf(")")



cdef void printres(int total, intopstack *stack) nogil:
    stdio.printf("%d = ", total)
    printexpr(stack, 0, True, True)
    stdio.printf("\n")



cdef int solve(int total, count *cnt, intestack *estack, intopstack *stack) nogil:
    cdef int diff
    cdef int bestsolution = limits.INT_MAX
    cdef unsigned a, b, v
    cdef intestack newestack
    cdef intopstack newopstack

    newopstack.nextopstack = stack

    if estack is not NULL and estack.nextestack is not NULL:
        b = estack.val
        a = estack.nextestack.val

        newestack.nextestack = estack.nextestack.nextestack
        newopstack.isop = True
        newopstack.end = stack.end.end

        # Commutating operations are tried only once
        if a <= b:
            # Don't try the right associative formula for the associative operators
            # (a + b) + c will be tried, no need to try a + (b + c) as well.
            # No need to try a + (b - c) either.
            if not (stack.isop and stack.op in (ord('+'), ord('-'))):
                newestack.val = a + b
                newopstack.op = b'+'
                sol = solve(total, cnt, &newestack, &newopstack)
                bestsolution = min(bestsolution, sol)

            # Don't multiply by 1
            if a != 1:
                # Left associativity only
                if not (stack.isop and stack.op in (ord('*'), ord('/'))):
                    newestack.val = a * b
                    newopstack.op = b'*'
                    sol = solve(total, cnt, &newestack, &newopstack)
                    bestsolution = min(bestsolution, sol)

        # Only strictly positive integers
        if a > b:
            newestack.val = a - b
            newopstack.op = b'-'
            sol = solve(total, cnt, &newestack, &newopstack)
            bestsolution = min(bestsolution, sol)

        # Only integers and don't divide by 1
        if b > 1 and a % b == 0:
            newestack.val = a // b
            newopstack.op = b'/'
            sol = solve(total, cnt, &newestack, &newopstack)
            bestsolution = min(bestsolution, sol)

    newestack.nextestack = estack
    newopstack.isop = False
    newopstack.end = stack

    cdef count *pcnt = cnt
    cdef count **ppcnt = &cnt
    while pcnt is not NULL:
        v = pcnt.value
        newestack.val = v
        newopstack.val = v

        if pcnt.count == 1:
            ppcnt[0] = pcnt.nextcount
            sol = solve(total, cnt, &newestack, &newopstack)
            ppcnt[0] = pcnt
        else:
            pcnt.count -= 1
            sol = solve(total, cnt, &newestack, &newopstack)
            pcnt.count += 1

        bestsolution = min(bestsolution, sol)
        ppcnt = &pcnt.nextcount
        pcnt = pcnt.nextcount

    if estack is not NULL and estack.nextestack is NULL:
        diff = total - estack.val
        if diff == 0:
            printres(total, stack)

        if diff < 0:
            diff = -diff

        bestsolution = min(bestsolution, diff)

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

    cdef count *counts = NULL
    c = Counter(values)
    counts = <count *>calloc(len(c), sizeof(counts[0]))

    for i, (v, n) in enumerate(c.items()):
        counts[i] = count(v, n, &counts[i + 1])

    counts[len(c) - 1].nextcount = NULL

    diff = solve(total, counts, NULL, NULL)
    if diff != 0:
        if (total > diff):
            solve(total - diff, counts, NULL, NULL)
        solve(total + diff, counts, NULL, NULL)

    free(counts)




if __name__ == '__main__':
    main()
