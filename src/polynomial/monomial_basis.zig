const std = @import("std");
const ArrayList = std.ArrayList;
const Bandersnatch = @import("../ecc/bandersnatch/bandersnatch.zig");
const Fr = Bandersnatch.Fr;

// from dataclasses import dataclass
// from typing import List
// from ecc import Fr
// from copy import deepcopy

pub const MonomialBasis = struct {
    //     Represents polynomials in coefficient form
    //     The coefficient corresponding to the lowest
    //     degree monomial is stored in the lowest index
    //     ie [1,2,3] = 3x^2 + 2x + 1
    coeffs: ArrayList(Fr),

    pub fn empty(allocator: std.mem.Allocator) MonomialBasis {
        return .{ .coeffs = ArrayList(Fr).init(allocator) };
    }

    pub fn deinit(self: *MonomialBasis) void {
        self.coeffs.deinit();
    }

    pub fn mul(self: *MonomialBasis, allocator: std.mem.Allocator, a: MonomialBasis, b: MonomialBasis) *MonomialBasis {
        self.coeffs = ArrayList(Fr).initCapacity(allocator, a.coeffs.items.len + b.coeffs.len - 1);
        self.coeffs.appendNTimes(Fr.zero(), self.coeffs.items.capacity);

        for (a.coeffs.items, 0..) |aval, i| {
            for (b.coeffs.items, 0..) |bval, j| {
                self.coeffs.items[i + j] += aval * bval;
            }
        }
        return self;
    }
    pub fn div(allocator: std.mem.Allocator, a: MonomialBasis, b: MonomialBasis) !MonomialBasis {
        std.debug.assert(a.coeffs.items.len >= b.coeffs.items.len);

        const az = try a.coeffs.clone();
        defer az.deinit();
        var o = ArrayList(Fr).init(allocator);
        var apos = a.coeffs.items.len - 1;
        var bpos = b.coeffs.items.len - 1;
        var diff = apos - bpos;

        diffloop: while (diff >= 0) {
            const quot = Fr.div(az.items[apos], b.coeffs.items[bpos]).?;
            try o.insert(0, quot);

            var i = bpos;
            blk: while (i >= 0) {
                az.items[diff + i] = Fr.sub(az.items[diff + i], Fr.mul(b.coeffs.items[i], quot));
                if (i == 0) {
                    break :blk;
                }
                i -= 1;
            }
            apos -= 1;

            if (diff == 0) {
                break :diffloop;
            }
            diff -= 1;
        }

        return .{ .coeffs = o };
    }

    pub fn evaluate(self: *MonomialBasis, x: Fr) Fr {
        var y = Fr.zero();
        var power_of_x = Fr.one();

        for (self.coeffs.items) |p_coeff| {
            y = Fr.add(y, Fr.mul(power_of_x, p_coeff));
            power_of_x = Fr.mul(power_of_x, x);
        }
        return y;
    }

    pub fn formalDerivative(self: *MonomialBasis, f: MonomialBasis) *MonomialBasis {
        self.coeffs.clearRetainingCapacity();
        for (f.coeffs.items, 1..) |c, n| {
            self.coeffs.append(c * Fr(n));
        }
        return self;
    }

    pub fn vanishingPoly(allocator: std.mem.Allocator, xs: ArrayList(Fr)) !MonomialBasis {
        var root = ArrayList(Fr).init(allocator);
        try root.append(Fr.one());

        for (xs.items) |x| {
            try root.insert(0, Fr.zero());
            for (0..root.items.len - 1) |j| {
                root.items[j] = Fr.sub(root.items[j], Fr.mul(root.items[j + 1], x));
            }
        }
        return .{ .coeffs = root };
    }

    pub fn eq(self: MonomialBasis, other: MonomialBasis) bool {
        if (self.coeffs.items.len != other.coeffs.items.len) return false;

        for (self.coeffs.items, other.coeffs.items) |a, b| {
            if (!a.eq(b)) return false;
        }
        return true;
    }
};

var allocator_test = std.testing.allocator;
test "Vanishing Polynomial on domain" {
    var xs = ArrayList(Fr).init(allocator_test);
    defer xs.deinit();
    try xs.appendSlice(&[_]Fr{ Fr.fromInteger(0), Fr.fromInteger(1), Fr.fromInteger(2), Fr.fromInteger(3), Fr.fromInteger(4), Fr.fromInteger(5) });

    var z = try MonomialBasis.vanishingPoly(allocator_test, xs);
    defer z.deinit();

    for (xs.items) |x| {
        const eval = z.evaluate(x);
        try std.testing.expect(eval.isZero());
    }
    const eval = z.evaluate(Fr.fromInteger(6));
    try std.testing.expect(!eval.isZero());
}

test "Polynomial Division" {
    // a = (x+1)(x+2) = x^2 + 3x + 2
    var acoeff = ArrayList(Fr).init(allocator_test);
    defer acoeff.deinit();
    try acoeff.appendSlice(&[_]Fr{ Fr.fromInteger(2), Fr.fromInteger(3), Fr.fromInteger(1) });
    const a = MonomialBasis{ .coeffs = acoeff };

    // b = (x+1)
    var bcoeff = ArrayList(Fr).init(allocator_test);
    defer bcoeff.deinit();
    try bcoeff.appendSlice(&[_]Fr{ Fr.fromInteger(1), Fr.fromInteger(1) });
    const b = MonomialBasis{ .coeffs = bcoeff };

    var result = try MonomialBasis.div(allocator_test, a, b);
    defer result.deinit();

    // Expected result should be (x+2)
    var expcoeff = ArrayList(Fr).init(allocator_test);
    defer expcoeff.deinit();
    try expcoeff.appendSlice(&[_]Fr{ Fr.fromInteger(2), Fr.fromInteger(1) });
    var expected = MonomialBasis{ .coeffs = expcoeff };

    try std.testing.expect(expected.eq(result));
}

// test "Derivative" {
//         # a = 6x^4 + 5x^3 + 10x^2 + 20x + 9
//         a = Polynomial([Fr(9), Fr(20), Fr(10), Fr(5), Fr(6)])
//         # the derivative of a is 24x^3 + 15x^2 + 20x + 20
//         expected_a_prime = Polynomial([Fr(20), Fr(20), Fr(15), Fr(24)])

//         got_a_prime = Polynomial._empty()
//         got_a_prime.formal_derivative(a)

//         self.assertEqual(got_a_prime, expected_a_prime)
// }

