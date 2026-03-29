// Copyright 2026 The Project Contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/*
 * Equalizer Core - Speech Optimization
 * 
 * Time-multiplexed 3-stage biquad cascade:
 *   Stage 0: HPF  @ 150 Hz   (rumble removal)
 *   Stage 1: Peak @ 2.5 kHz  (speech boost, +6dB)
 *   Stage 2: LPF  @ 5 kHz    (noise reduction)
 *
 * Uses a single multiplier with a 5-state FSM.
 * Coefficients in Q3.15 format (1 sign + 3 integer + 14 fractional bits).
 * Data path is 24-bit signed (Q1.23).
 * Internal accumulator is 48-bit signed.
 *
 * Latency: ~35 system clocks per sample.
 */
module equalizer_core (
    input  wire        clk,
    input  wire        rst_n,     // unused, kept for interface compat
    input  wire        ce,
    input  wire signed [23:0] sample_in,
    output reg  signed [23:0] sample_out,
    output reg         ready
);

    // ── Coefficient ROM (combinational) ──────────────────────
    // Index = stage*5 + tap  (0..14)
    reg signed [17:0] coeff;
    reg [4:0] step;
    always @(*) begin
        case (step)
            // Stage 0: HPF @ 200 Hz
            5'd0:  coeff =  18'sd32153;   // HPF b0
            5'd1:  coeff = -18'sd64305;   // HPF b1
            5'd2:  coeff =  18'sd32153;   // HPF b2
            5'd3:  coeff = -18'sd64294;   // HPF a1
            5'd4:  coeff =  18'sd31549;   // HPF a2
            // Stage 1: Peaking @ 1.8 kHz, +9dB
            5'd5:  coeff =  18'sd37635;   // Peak b0
            5'd6:  coeff = -18'sd58439;   // Peak b1
            5'd7:  coeff =  18'sd22547;   // Peak b2
            5'd8:  coeff = -18'sd58439;   // Peak a1
            5'd9:  coeff =  18'sd27414;   // Peak a2
            // Stage 2: LPF @ 3.8 kHz
            5'd10: coeff =  18'sd1547;    // LPF b0
            5'd11: coeff =  18'sd3093;    // LPF b1
            5'd12: coeff =  18'sd1547;    // LPF b2
            5'd13: coeff = -18'sd42545;   // LPF a1
            5'd14: coeff =  18'sd15963;   // LPF a2
            default: coeff = 18'sd0;
        endcase
    end

    // ── History registers per stage ──────────────────────────
    reg signed [23:0] x1 [0:2];   // x[n-1]
    reg signed [23:0] x2 [0:2];   // x[n-2]
    reg signed [23:0] y1 [0:2];   // y[n-1]
    reg signed [23:0] y2 [0:2];   // y[n-2]

    // ── FSM ──────────────────────────────────────────────────
    localparam S_IDLE  = 3'd0;   // Wait for ce
    localparam S_LOAD  = 3'd1;   // Select data for this tap
    localparam S_MAC   = 3'd2;   // Multiply-Accumulate
    localparam S_QUANT = 3'd3;   // Quantize result (acc is now valid)
    localparam S_DONE  = 3'd4;   // Pulse ready

    reg [2:0]  state    = S_IDLE;
    reg [1:0]  stage    = 0;
    reg [2:0]  tap      = 0;
    reg signed [23:0] stage_in  = 0;   // Input to current stage
    reg signed [23:0] mac_data  = 0;   // Operand for multiply
    reg signed [47:0] acc       = 0;

    // ── Saturating quantizer (combinational) ─────────────────
    // Converts acc (Q-accumulated) to 24-bit Q1.23 with saturation.
    // The useful result sits in acc[38:15].
    // Overflow check: bits [47:38] must be all-same (sign extension).
    wire signed [23:0] sat_result;
    wire overflow_pos = ~acc[47] &  (|acc[46:38]);
    wire overflow_neg =  acc[47] & ~(&acc[46:38]);
    assign sat_result = overflow_pos ? 24'sh7FFFFF :
                        overflow_neg ? 24'sh800000 :
                        acc[38:15];

    integer i;

    always @(posedge clk) begin
        case (state)
            // ────────────────────────────────────────────────
            S_IDLE: begin
                ready <= 1'b0;
                if (ce) begin
                    stage_in <= sample_in;
                    stage    <= 0;
                    tap      <= 0;
                    step     <= 0;
                    acc      <= 0;
                    state    <= S_LOAD;
                end
            end

            // ────────────────────────────────────────────────
            S_LOAD: begin
                // Select the data operand for the current tap
                case (tap)
                    3'd0: mac_data <= stage_in;       // x[n]
                    3'd1: mac_data <= x1[stage];      // x[n-1]
                    3'd2: mac_data <= x2[stage];      // x[n-2]
                    3'd3: mac_data <= y1[stage];      // y[n-1]
                    3'd4: mac_data <= y2[stage];      // y[n-2]
                    default: mac_data <= 0;
                endcase
                state <= S_MAC;
            end

            // ────────────────────────────────────────────────
            S_MAC: begin
                // b-coefficients (tap 0,1,2): add
                // a-coefficients (tap 3,4):   subtract (standard biquad form)
                if (tap >= 3'd3)
                    acc <= acc - (mac_data * coeff);
                else
                    acc <= acc + (mac_data * coeff);

                if (tap == 3'd4) begin
                    // All 5 taps done for this stage.
                    // acc will be updated by non-blocking next cycle.
                    // Go to QUANT to read the settled value.
                    state <= S_QUANT;
                end else begin
                    tap  <= tap + 1'b1;
                    step <= step + 1'b1;
                    state <= S_LOAD;
                end
            end

            // ────────────────────────────────────────────────
            S_QUANT: begin
                // acc now contains the FINAL sum including a2.
                // sat_result is the saturated 24-bit output (combinational wire).

                // Update history for this stage
                x2[stage] <= x1[stage];
                x1[stage] <= stage_in;
                y2[stage] <= y1[stage];
                y1[stage] <= sat_result;

                // Output / cascade to next stage
                sample_out <= sat_result;

                if (stage == 2'd2) begin
                    // All 3 stages complete
                    state <= S_DONE;
                end else begin
                    // Advance to next stage
                    stage_in <= sat_result;
                    stage    <= stage + 1'b1;
                    tap      <= 0;
                    step     <= step + 1'b1;
                    acc      <= 0;
                    state    <= S_LOAD;
                end
            end

            // ────────────────────────────────────────────────
            S_DONE: begin
                ready <= 1'b1;
                state <= S_IDLE;
            end
        endcase
    end

    // History init (power-on)
    initial begin
        for (i = 0; i < 3; i = i + 1) begin
            x1[i] = 0; x2[i] = 0;
            y1[i] = 0; y2[i] = 0;
        end
        sample_out = 0;
        ready = 0;
    end

endmodule
