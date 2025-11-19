pragma circom 2.2.0;

include "utils/dctq_step.circom";

component main { public [step_in] } = DCTQHash(16, 8);