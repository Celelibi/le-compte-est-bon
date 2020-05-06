#!/usr/bin/env python3

import sys
import random
from collections import Counter
from cpython cimport PyObject_Calloc as calloc, PyObject_Free as free
from libc cimport limits



cdef struct intestack:
    int val
    intestack *nextestack



cdef struct intopstack:
    bint isop
    char op
    int val
    intopstack *nextopstack



cdef struct count:
    unsigned char value
    unsigned char count
    count *nextcount



prio = {'+': 0, '-': 0, '*': 1, '/': 1}
assoc = {'+': True, '-': False, '*': True, '/': False}

cdef exprstr_(stack):
    global prio, assoc

    top = stack.pop()
    opprio = prio.get(top, 2)
    opassoc = assoc.get(top, True)

    if opprio == 2:
        return top, opprio, opassoc

    b, bprio, bassoc = exprstr_(stack)
    a, aprio, aassoc = exprstr_(stack)

    if opprio > aprio:
        a = "(%s)" % a
    if opprio > bprio or (opprio == bprio and not opassoc):
        b = "(%s)" % b

    expr = "%s %s %s" % (a, top, b)
    return expr, opprio, opassoc


cdef str exprstr(intopstack *stack):
    cdef intopstack *p = stack
    cdef list l = []
    while p is not NULL:
        if p.isop:
            l.append(chr(p.op))
        else:
            l.append(str(p.val))
        p = p.nextopstack

    l.reverse()
    ret = exprstr_(l)
    assert l == []
    return ret[0]



cdef int solve(int total, count *cnt, intestack *estack, intopstack *stack):
    cdef int bestsolution = limits.INT_MAX
    cdef unsigned a, b, v
    cdef intestack newestack
    cdef intopstack newopstack

    newopstack.nextopstack = stack

    if estack is not NULL and estack.nextestack is not NULL:
        assert stack is not NULL
        b = estack.val
        a = estack.nextestack.val

        newestack.nextestack = estack.nextestack.nextestack
        newopstack.isop = True

        # Commutating operations are tried only once
        if a <= b:
            # Don't try the right associative formula for the associative operators
            # (a + b) + c will be tried, no need to try a + (b + c) as well.
            # No need to try a + (b - c) either.
            if not (stack is not NULL and stack.isop and stack.op in (ord('+'), ord('-'))):
                newestack.val = a + b
                newopstack.op = b'+'
                sol = solve(total, cnt, &newestack, &newopstack)
                bestsolution = min(bestsolution, sol)

            # Don't multiply by 1
            if a != 1:
                # Left associativity only
                if not (stack is not NULL and stack.isop and stack.op in (ord('*'), ord('/'))):
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
        if total == estack.val:
            print(total, "=", exprstr(stack))
        bestsolution = min(bestsolution, abs(total - estack.val))

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

    cdef count *counts
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
