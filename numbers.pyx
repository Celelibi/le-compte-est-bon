#!/usr/bin/env python3

import sys
import random
from collections import Counter
from cython import parallel as cypar

from libc cimport limits, stdio, stdlib
cimport openmp as omp



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



cdef int rightmost(intopstack *stack, char op) nogil:
    while stack.isop and stack.op == op:
        stack = stack.nextopstack
    return stack.val



cdef int cmp(intopstack *expr1, intopstack *expr2) nogil:
    cdef int res

    res = expr1.isop - expr2.isop
    if res != 0:
        return res

    # Either both are operators or both are not
    if not expr1.isop:
        return expr1.val - expr2.val

    # Compare the operators themselves
    res = expr1.op - expr2.op
    if res != 0:
        return res

    # Compare the right hand side of both expressions
    res = cmp(expr1.nextopstack, expr2.nextopstack)
    if res != 0:
        return res

    # In last resort, compare the left hand side of both expressions
    return cmp(expr1.nextopstack.end, expr2.nextopstack.end)



cdef int solve(int total, count *cnt, intopstack *stack) nogil:
    cdef int diff
    cdef int bestsolution = limits.INT_MAX
    cdef unsigned a, b, v
    cdef intopstack newopstack
    cdef intopstack *lhs
    cdef intopstack *rhs
    cdef bint skip
    cdef int rightval

    if stack is not NULL and stack.end is NULL:
        diff = total - stack.val
        if diff == 0:
            printres(total, stack)
        if diff < 0:
            diff = -diff
        bestsolution = diff

    newopstack.nextopstack = stack

    if stack is not NULL and stack.end is not NULL:
        rhs = stack
        lhs = stack.end
        a = lhs.val
        b = rhs.val

        newopstack.isop = True
        newopstack.end = stack.end.end

        # Don't try the some associative formula for the associative operators.
        # Try to keep the numbers in increasing order and the formula left
        # associative.
        # i.e. skip a + (b + c) and prefer (a + b) + c
        # Skip (a + c) + b if c > b
        # The function cmp define a total order on expressions to avoid testing
        # both a + b and b + a
        #
        # Also skip a + (b - c), (a + b) - c is always prefered
        # Also skip (a - b) + c, (a + c) - b is always prefered
        skip = (rhs.isop and rhs.op in (b'-', b'+'))
        skip = skip or (lhs.isop and lhs.op == b'-')
        if not skip:
            rightval = rightmost(lhs, b'+')
            skip = skip or (rightval > rhs.val)
            if not skip and rightval == rhs.val:
                skip = skip or (cmp(lhs, rhs) > 0)

        if not skip:
            newopstack.op = b'+'
            newopstack.val = a + b
            sol = solve(total, cnt, &newopstack)
            bestsolution = min(bestsolution, sol)

        # Don't multiply by 1
        if a != 1 and b != 1:
            # Left associativity only
            skip = (rhs.isop and rhs.op in (b'/', b'*'))
            skip = skip or (lhs.isop and lhs.op == b'/')
            if not skip:
                rightval = rightmost(lhs, b'*')
                skip = skip or (rightval > rhs.val)
                if not skip and rightval == rhs.val:
                    skip = skip or (cmp(lhs, rhs) > 0)

            if not skip:
                newopstack.op = b'*'
                newopstack.val = a * b
                sol = solve(total, cnt, &newopstack)
                bestsolution = min(bestsolution, sol)

        # Only strictly positive integers
        if a > b:
            newopstack.op = b'-'
            newopstack.val = a - b
            sol = solve(total, cnt, &newopstack)
            bestsolution = min(bestsolution, sol)

        # Only integers and don't divide by 1
        if b > 1 and a % b == 0:
            newopstack.op = b'/'
            newopstack.val = a // b
            sol = solve(total, cnt, &newopstack)
            bestsolution = min(bestsolution, sol)

    newopstack.isop = False
    newopstack.end = stack

    cdef count *pcnt = cnt
    cdef count **ppcnt = &cnt
    while pcnt is not NULL:
        v = pcnt.value
        newopstack.val = v

        if pcnt.count == 1:
            ppcnt[0] = pcnt.nextcount
            sol = solve(total, cnt, &newopstack)
            ppcnt[0] = pcnt
        else:
            pcnt.count -= 1
            sol = solve(total, cnt, &newopstack)
            pcnt.count += 1

        bestsolution = min(bestsolution, sol)
        ppcnt = &pcnt.nextcount
        pcnt = pcnt.nextcount

    return bestsolution


cdef class calloc(object):
    cdef void *ptr
    cdef size_t nmemb
    cdef size_t size

    def __init__(self, nmemb, size):
        self.ptr = NULL
        self.nmemb = nmemb
        self.size = size

    cdef void *__enter__(self) nogil:
        self.ptr = stdlib.calloc(self.nmemb, self.size)
        return self.ptr

    def __exit__(self, *exc):
        stdlib.free(self.ptr)
        return False



cdef int solve_par(int total, list values):
    cdef size_t ncnt
    cdef int i, p, j, k
    cdef void *ptr
    cdef count *counts
    cdef count *pcnt1
    cdef count *pcnt2
    cdef count **ppcnt1
    cdef count **ppcnt2
    cdef intopstack opstack1, opstack2
    cdef int sol, bestsolution, threadbest
    cdef int *pthreadbest
    cdef int *pbestsolution
    cdef omp.omp_lock_t mutex

    bestsolution = limits.INT_MAX
    pbestsolution = &bestsolution
    omp.omp_init_lock(&mutex)

    c = Counter(values)
    ncnt = len(c)
    counts = NULL
    cntsz = sizeof(counts[0])

    with nogil, cypar.parallel(), gil, calloc(ncnt, cntsz) as ptr, nogil:
        counts = <count *>ptr
        # Every thread need their own linked list of counts
        with gil:
            for i, (v, n) in enumerate(c.items()):
                counts[i] = count(v, n, &counts[i + 1])

        # Don't link the last one
        counts[ncnt - 1].nextcount = NULL

        # Older versions of cython require the GIL for this
        with gil:
            opstack1 = intopstack(False, 0, 0, NULL, NULL)
            opstack2 = intopstack(False, 0, 0, NULL, NULL)

        threadbest = limits.INT_MAX
        pthreadbest = &threadbest
        for p in cypar.prange(ncnt**2, schedule='dynamic'):
            j = p // ncnt
            k = p % ncnt
            pcnt1 = &counts[j]
            pcnt2 = &counts[k]

            if j == k and pcnt1.count < 2:
                continue

            ppcnt1 = &counts if j == 0 else &counts[j - 1].nextcount
            ppcnt2 = &counts if k == 0 else &counts[k - 1].nextcount

            pcnt1.count -= 1
            pcnt2.count -= 1

            # Delink the value counters if they reached 0
            if j <= k:
                if pcnt2.count == 0:
                    ppcnt2[0] = pcnt2.nextcount
                if pcnt1.count == 0:
                    ppcnt1[0] = pcnt1.nextcount
            elif j > k:
                if pcnt1.count == 0:
                    ppcnt1[0] = pcnt1.nextcount
                if pcnt2.count == 0:
                    ppcnt2[0] = pcnt2.nextcount

            # Prepare the stacks
            opstack1.val = pcnt1.value
            opstack2.val = pcnt2.value
            opstack2.nextopstack = &opstack1
            opstack2.end = &opstack1

            sol = solve(total, counts, &opstack2)

            # Relink the counters
            ppcnt2[0] = pcnt2
            ppcnt1[0] = pcnt1

            pcnt2.count += 1
            pcnt1.count += 1

            pthreadbest[0] = min(pthreadbest[0], sol)

        omp.omp_set_lock(&mutex)
        pbestsolution[0] = min(pbestsolution[0], pthreadbest[0])
        omp.omp_unset_lock(&mutex)

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
