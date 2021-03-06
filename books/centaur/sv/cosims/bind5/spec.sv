// Bind Cosim Test
// Copyright (C) 2016 Apple, Inc.
//
// License: (An MIT/X11-style license)
//
//   Permission is hereby granted, free of charge, to any person obtaining a
//   copy of this software and associated documentation files (the "Software"),
//   to deal in the Software without restriction, including without limitation
//   the rights to use, copy, modify, merge, publish, distribute, sublicense,
//   and/or sell copies of the Software, and to permit persons to whom the
//   Software is furnished to do so, subject to the following conditions:
//
//   The above copyright notice and this permission notice shall be included in
//   all copies or substantial portions of the Software.
//
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//   DEALINGS IN THE SOFTWARE.
//
// Original author: Jared Davis

module myand (output [3:0] o, input [3:0] a, b);
   assign o = a & b;
endmodule

module sub (input logic [7:0] in,
	    output wire [7:0] out);

   wire [3:0] i1, i0;
   assign {i1, i0} = in;

   wire [3:0] o0;
   assign out = {o0};

endmodule

module spec (input logic [127:0] in,
	     output wire [127:0] out);

   sub mysub1(in[7:0], out[7:0]);
   sub mysub2(in[15:8], out[15:8]);

   // This isn't supported by the simple VL bindelim, because we don't know
   // that we're changing all instances of sub.
   bind sub : mysub1 myand g0 (o0, i0, i1);

endmodule

