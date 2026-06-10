# SIMT ALU Opcode Specification

## Parameters
- LANES: number of parallel lanes (default: 8)
- DATA_W: per-lane data width (default: 32)

## Operand Types
- src_a[lane] and src_b[lane] are treated as DATA_W-bit unsigned or 2's complement integers depending on the operation.
- SLT uses signed comparison by default in this spec (can be switched to unsigned later if desired).

## Opcode Map (4-bit)
- 0x0 : ADD  (result = A + B)
- 0x1 : SUB  (result = A - B)
- 0x2 : MUL  (result = (A * B) lower DATA_W bits)
- 0x3 : AND  (result = A & B)
- 0x4 : OR   (result = A | B)
- 0x5 : XOR  (result = A ^ B)
- 0x6 : SLT  (result = (signed(A) < signed(B)) ? 1 : 0)
- others: reserved (result = 0 for active lanes)

## Predication (lane_mask)
For each lane i:
- if lane_mask[i] == 1: compute result normally
- if lane_mask[i] == 0: result[i] = src_a[i] (pass-through)

## Flags
- zero_flag[i] = (result[i] == 0)

(Additional flags like negative/carry/overflow can be added later.)
