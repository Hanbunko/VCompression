pragma circom 2.2.0;

include "utils/hashers.circom";
include "utils/pixels.circom";
include "../node_modules/circomlib/circuits/comparators.circom";

/*
    Transformation called DCTQ (DCT + Quantization)
    Together with Encoding we get a full JPEG Compression.

    A block is a 8*8 sub-image.

    For a HD (1280*720) image:
    8 rows per step on special reshaped 160*5760 image mapping the original image
    Each step processes 8 rows × 160 pixels = 20 blocks
    Total would have 720 steps

    3-digit approximated DCT (scaled by 1000).
*/

template DCTQHash(width, rowCount) {
    signal input step_in[2];
    signal output step_out[2];

    // inputs
    signal input row_orig [rowCount][width];
    signal input row_tran [rowCount][width];

    var decompressedWidth = width * 10;
    signal decompressed_orig[rowCount][decompressedWidth][3];
    signal decompressed_tran[rowCount][decompressedWidth][3];

    component decompressor_orig[rowCount][width];
    component decompressor_tran[rowCount][width];

    for (var r = 0; r < rowCount; r++) {
        for (var i = 0; i < width; i++) {
            decompressor_orig[r][i] = Decompressor();
            decompressor_orig[r][i].in <== row_orig[r][i];

            decompressor_tran[r][i] = Decompressor();
            decompressor_tran[r][i].in <== row_tran[r][i];

            for (var j = 0; j < 10; j++) {
                decompressed_orig[r][i*10+j] <== decompressor_orig[r][i].out[j];
                decompressed_tran[r][i*10+j] <== decompressor_tran[r][i].out[j];
            }
        }
    }

    // block by block
    var numBlocksH = decompressedWidth \ 8;

    component dctqVerifier[numBlocksH][3];

    for (var bh = 0; bh < numBlocksH; bh++) {
        for (var color = 0; color < 3; color++) {
            dctqVerifier[bh][color] = DCTQVerifier(color);

            // Extract 8×8 block from 8 rows
            for (var i = 0; i < 8; i++) {
                for (var j = 0; j < 8; j++) {
                    dctqVerifier[bh][color].orig[i][j] <== decompressed_orig[i][bh*8 + j][color];
                    dctqVerifier[bh][color].comp[i][j] <== decompressed_tran[i][bh*8 + j][color];
                }
            }
        }
    }

    // Hash 8 rows -by- 8 rows
    signal hashes_orig[rowCount];
    signal hashes_tran[rowCount];

    component row_hasher_orig[rowCount];
    component row_hasher_tran[rowCount];

    for (var i = 0; i < rowCount; i++) {
        row_hasher_orig[i] = ArrayHasher(width);
        row_hasher_orig[i].array <== row_orig[i];
        hashes_orig[i] <== row_hasher_orig[i].hash;

        row_hasher_tran[i] = ArrayHasher(width);
        row_hasher_tran[i].array <== row_tran[i];
        hashes_tran[i] <== row_hasher_tran[i].hash;
    }

    component final_hasher_orig = ArrayHasher(rowCount);
    component final_hasher_tran = ArrayHasher(rowCount);

    final_hasher_orig.array <== hashes_orig;
    final_hasher_tran.array <== hashes_tran;

    component state_hasher = PairHasher();
    state_hasher.a <== step_in[0];
    state_hasher.b <== final_hasher_orig.hash;

    component tran_hasher = PairHasher();
    tran_hasher.a <== step_in[1];
    tran_hasher.b <== final_hasher_tran.hash;

    step_out[0] <== state_hasher.hash;
    step_out[1] <== tran_hasher.hash;
}

// Verifier of DCTQ transformation per block
template DCTQVerifier(channel) {
    signal input orig[8][8];      // Original sub-image
    signal input comp[8][8];      // Transformed

    // Q table
    var Q[8][8];

    if (channel == 0) {
        // Luminance
        Q[0][0]=16; Q[0][1]=11; Q[0][2]=10; Q[0][3]=16; Q[0][4]=24; Q[0][5]=40; Q[0][6]=51; Q[0][7]=61;
        Q[1][0]=12; Q[1][1]=12; Q[1][2]=14; Q[1][3]=19; Q[1][4]=26; Q[1][5]=58; Q[1][6]=60; Q[1][7]=55;
        Q[2][0]=14; Q[2][1]=13; Q[2][2]=16; Q[2][3]=24; Q[2][4]=40; Q[2][5]=57; Q[2][6]=69; Q[2][7]=56;
        Q[3][0]=14; Q[3][1]=17; Q[3][2]=22; Q[3][3]=29; Q[3][4]=51; Q[3][5]=87; Q[3][6]=80; Q[3][7]=62;
        Q[4][0]=18; Q[4][1]=22; Q[4][2]=37; Q[4][3]=56; Q[4][4]=68; Q[4][5]=109; Q[4][6]=103; Q[4][7]=77;
        Q[5][0]=24; Q[5][1]=35; Q[5][2]=55; Q[5][3]=64; Q[5][4]=81; Q[5][5]=104; Q[5][6]=113; Q[5][7]=92;
        Q[6][0]=49; Q[6][1]=64; Q[6][2]=78; Q[6][3]=87; Q[6][4]=103; Q[6][5]=121; Q[6][6]=120; Q[6][7]=101;
        Q[7][0]=72; Q[7][1]=92; Q[7][2]=95; Q[7][3]=98; Q[7][4]=112; Q[7][5]=100; Q[7][6]=103; Q[7][7]=99;
    } else {
        // Chrominance
        Q[0][0]=17; Q[0][1]=18; Q[0][2]=24; Q[0][3]=47; Q[0][4]=99; Q[0][5]=99; Q[0][6]=99; Q[0][7]=99;
        Q[1][0]=18; Q[1][1]=21; Q[1][2]=26; Q[1][3]=66; Q[1][4]=99; Q[1][5]=99; Q[1][6]=99; Q[1][7]=99;
        Q[2][0]=24; Q[2][1]=26; Q[2][2]=56; Q[2][3]=99; Q[2][4]=99; Q[2][5]=99; Q[2][6]=99; Q[2][7]=99;
        Q[3][0]=47; Q[3][1]=66; Q[3][2]=99; Q[3][3]=99; Q[3][4]=99; Q[3][5]=99; Q[3][6]=99; Q[3][7]=99;
        Q[4][0]=99; Q[4][1]=99; Q[4][2]=99; Q[4][3]=99; Q[4][4]=99; Q[4][5]=99; Q[4][6]=99; Q[4][7]=99;
        Q[5][0]=99; Q[5][1]=99; Q[5][2]=99; Q[5][3]=99; Q[5][4]=99; Q[5][5]=99; Q[5][6]=99; Q[5][7]=99;
        Q[6][0]=99; Q[6][1]=99; Q[6][2]=99; Q[6][3]=99; Q[6][4]=99; Q[6][5]=99; Q[6][6]=99; Q[6][7]=99;
        Q[7][0]=99; Q[7][1]=99; Q[7][2]=99; Q[7][3]=99; Q[7][4]=99; Q[7][5]=99; Q[7][6]=99; Q[7][7]=99;
    }

    signal quantized_signed[8][8];
    for (var i = 0; i < 8; i++) {
        for (var j = 0; j < 8; j++) {
            quantized_signed[i][j] <== comp[i][j] - 128;
        }
    }

    // Apply approximated DCTQ
    component dctq = ApproximatedDCTQ2D();
    for (var i = 0; i < 8; i++) {
        for (var j = 0; j < 8; j++) {
            dctq.block[i][j] <== orig[i][j];
            dctq.quantized[i][j] <== quantized_signed[i][j];
            dctq.divisor[i][j] <== Q[i][j];
        }
    }
}

// Approximated 2D-DCTQ
template ApproximatedDCTQ2D() {
    signal input block[8][8];
    signal input quantized[8][8];
    signal input divisor[8][8];

    signal centered[8][8];
    for (var i = 0; i < 8; i++) {
        for (var j = 0; j < 8; j++) {
            centered[i][j] <== block[i][j] - 128;
        }
    }

    // Apply 1D-DCT for each row
    signal rowSums[8][8];
    component dctRows[8];
    for (var i = 0; i < 8; i++) {
        dctRows[i] = ApproximatedDCT1DSum();
        for (var j = 0; j < 8; j++) {
            dctRows[i].inp[j] <== centered[i][j];
        }
        for (var j = 0; j < 8; j++) {
            rowSums[i][j] <== dctRows[i].sum[j];
        }
    }

    // Apply 1D-DCT at each column & the last check step
    component dctColsVerifier[8];
    for (var j = 0; j < 8; j++) {
        dctColsVerifier[j] = ApproximatedDCT1DSumWithQuantVerify();
        for (var i = 0; i < 8; i++) {
            dctColsVerifier[j].inp[i] <== rowSums[i][j];
            dctColsVerifier[j].quantized[i] <== quantized[i][j];
            dctColsVerifier[j].divisor[i] <== divisor[i][j];
        }
    }
}

// 1D DCT that outputs sums (before division by 1000)
template ApproximatedDCT1DSum() {
    signal input inp[8];
    signal output sum[8];

    // DCT matrix
    var dct[8][8];
    dct[0][0]=354; dct[0][1]=354; dct[0][2]=354; dct[0][3]=354; dct[0][4]=354; dct[0][5]=354; dct[0][6]=354; dct[0][7]=354;
    dct[1][0]=490; dct[1][1]=416; dct[1][2]=278; dct[1][3]=98; dct[1][4]=-98; dct[1][5]=-278; dct[1][6]=-416; dct[1][7]=-490;
    dct[2][0]=462; dct[2][1]=191; dct[2][2]=-191; dct[2][3]=-462; dct[2][4]=-462; dct[2][5]=-191; dct[2][6]=191; dct[2][7]=462;
    dct[3][0]=416; dct[3][1]=-98; dct[3][2]=-490; dct[3][3]=-278; dct[3][4]=278; dct[3][5]=490; dct[3][6]=98; dct[3][7]=-416;
    dct[4][0]=354; dct[4][1]=-354; dct[4][2]=-354; dct[4][3]=354; dct[4][4]=354; dct[4][5]=-354; dct[4][6]=-354; dct[4][7]=354;
    dct[5][0]=278; dct[5][1]=-490; dct[5][2]=98; dct[5][3]=416; dct[5][4]=-416; dct[5][5]=-98; dct[5][6]=490; dct[5][7]=-278;
    dct[6][0]=191; dct[6][1]=-462; dct[6][2]=462; dct[6][3]=-191; dct[6][4]=-191; dct[6][5]=462; dct[6][6]=-462; dct[6][7]=191;
    dct[7][0]=98; dct[7][1]=-278; dct[7][2]=416; dct[7][3]=-490; dct[7][4]=490; dct[7][5]=-416; dct[7][6]=278; dct[7][7]=-98;

    // Compute DCT sums: sum[i] = 1000 * sum(dct[i][j] * inp[j])
    for (var i = 0; i < 8; i++) {
        var s = 0;
        for (var j = 0; j < 8; j++) {
            s += dct[i][j] * inp[j];
        }
        sum[i] <== s;
    }
}

template ApproximatedDCT1DSumWithQuantVerify() {
    signal input inp[8];        // Input
    signal input quantized[8];  // Output
    signal input divisor[8];    // Q table divisor

    var dct[8][8];
    dct[0][0]=354; dct[0][1]=354; dct[0][2]=354; dct[0][3]=354; dct[0][4]=354; dct[0][5]=354; dct[0][6]=354; dct[0][7]=354;
    dct[1][0]=490; dct[1][1]=416; dct[1][2]=278; dct[1][3]=98; dct[1][4]=-98; dct[1][5]=-278; dct[1][6]=-416; dct[1][7]=-490;
    dct[2][0]=462; dct[2][1]=191; dct[2][2]=-191; dct[2][3]=-462; dct[2][4]=-462; dct[2][5]=-191; dct[2][6]=191; dct[2][7]=462;
    dct[3][0]=416; dct[3][1]=-98; dct[3][2]=-490; dct[3][3]=-278; dct[3][4]=278; dct[3][5]=490; dct[3][6]=98; dct[3][7]=-416;
    dct[4][0]=354; dct[4][1]=-354; dct[4][2]=-354; dct[4][3]=354; dct[4][4]=354; dct[4][5]=-354; dct[4][6]=-354; dct[4][7]=354;
    dct[5][0]=278; dct[5][1]=-490; dct[5][2]=98; dct[5][3]=416; dct[5][4]=-416; dct[5][5]=-98; dct[5][6]=490; dct[5][7]=-278;
    dct[6][0]=191; dct[6][1]=-462; dct[6][2]=462; dct[6][3]=-191; dct[6][4]=-191; dct[6][5]=462; dct[6][6]=-462; dct[6][7]=191;
    dct[7][0]=98; dct[7][1]=-278; dct[7][2]=416; dct[7][3]=-490; dct[7][4]=490; dct[7][5]=-416; dct[7][6]=278; dct[7][7]=-98;

    // final DCT sums
    component verifier[8];

    for (var i = 0; i < 8; i++) {
        var sum = 0;
        for (var j = 0; j < 8; j++) {
            sum += dct[i][j] * inp[j];
        }

        // Combined verification: |sum - 1000×divisor×quantized| < 1000×(divisor + 1)
        verifier[i] = CombinedDCTQVerifier();
        verifier[i].sum <== sum;
        verifier[i].quantized <== quantized[i];
        verifier[i].divisor <== divisor[i];
    }
}

// A Range check for a Relaxed version of our requirement
// by combining two range checks via Triangle equility
// i.e. |sum - 1000×divisor×quantized| < 1000×(divisor + 1)
template CombinedDCTQVerifier() {
    signal input sum;
    signal input quantized;
    signal input divisor;

    signal product <== 1000 * divisor * quantized;

    signal bound <== 1000 * (divisor + 1);

    component lt = LessThan(32);
    lt.in[0] <== sum - product + bound;
    lt.in[1] <== 2 * bound;
    lt.out === 1;
}