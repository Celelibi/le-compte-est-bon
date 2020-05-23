#!/usr/bin/env python3

import sys
import random
from collections import Counter
from cython import parallel as cypar

from libc cimport limits, stdio, stdlib
cimport openmp as omp



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



cdef omp.omp_lock_t printmutex



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
    omp.omp_set_lock(&printmutex)
    stdio.printf("%d = ", total)
    printexpr(stack, 0, True, True)
    stdio.printf("\n")
    omp.omp_unset_lock(&printmutex)



cdef int solve(int total, count *cnt, intestack *estack, intopstack *stack) nogil:
    cdef int diff
    cdef int bestsolution = limits.INT_MAX
    cdef unsigned a, b, v
    cdef intestack newestack
    cdef intopstack newopstack

    if estack is not NULL and estack.nextestack is NULL:
        diff = total - estack.val
        if diff == 0:
            printres(total, stack)
        if diff < 0:
            diff = -diff
        bestsolution = diff

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

    return bestsolution



cdef int solve_par(int total, list values):
    cdef size_t ncnt
    cdef int i, j
    cdef count *counts
    cdef count *pcnt
    cdef count **ppcnt
    cdef intestack estack
    cdef intopstack opstack
    cdef int sol, bestsolution, threadbest
    cdef int *pthreadbest
    cdef int *pbestsolution
    cdef omp.omp_lock_t mutex

    bestsolution = limits.INT_MAX
    pbestsolution = &bestsolution
    omp.omp_init_lock(&mutex)

    c = Counter(values)

    with nogil, cypar.parallel():
        counts = NULL
        # Every thread need their own linked list of counts
        with gil:
            ncnt = len(c)
            counts = <count *>stdlib.calloc(ncnt, sizeof(counts[0]))

            for i, (v, n) in enumerate(c.items()):
                counts[i] = count(v, n, &counts[i + 1])

        # Don't link the last one
        counts[ncnt - 1].nextcount = NULL

        # Older versions of cython require the GIL for this
        with gil:
            estack = intestack(0, NULL)
            opstack = intopstack(False, 0, 0, NULL, NULL)

        threadbest = limits.INT_MAX
        pthreadbest = &threadbest
        for j in cypar.prange(ncnt, schedule='dynamic'):
            # Get the j-th element in counts
            pcnt = &counts[j]
            ppcnt = &counts
            if j > 0:
                ppcnt = &counts[j - 1].nextcount

            estack.val = pcnt.value
            opstack.val = pcnt.value

            if pcnt.count == 1:
                ppcnt[0] = pcnt.nextcount
                sol = solve(total, counts, &estack, &opstack)
                ppcnt[0] = pcnt
            else:
                pcnt.count -= 1
                sol = solve(total, counts, &estack, &opstack)
                pcnt.count += 1

            pthreadbest[0] = min(pthreadbest[0], sol)

        omp.omp_set_lock(&mutex)
        pbestsolution[0] = min(pbestsolution[0], pthreadbest[0])
        omp.omp_unset_lock(&mutex)


        with gil:
            stdlib.free(counts)

    omp.omp_destroy_lock(&mutex)

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

    diff = solve_par(total, values)
    if diff != 0:
        if (total > diff):
            solve_par(total - diff, values)
        solve_par(total + diff, values)



if __name__ == '__main__':
    omp.omp_init_lock(&printmutex)
    main()
    omp.omp_destroy_lock(&printmutex)
