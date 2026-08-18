#include "adpcm.h"

const int16_t ImaAdpcm::STEP_TABLE[89] = {
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 
    19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 
    50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 
    130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 
    337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 
    876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 
    2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 
    5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 
    15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767
};

const int8_t ImaAdpcm::INDEX_TABLE[16] = {
    -1, -1, -1, -1, 2, 4, 6, 8,
    -1, -1, -1, -1, 2, 4, 6, 8
};

ImaAdpcm::ImaAdpcm()
    : _predictedSample(0), _stepIndex(0) {}

void ImaAdpcm::reset() {
    _predictedSample = 0;
    _stepIndex = 0;
}

uint8_t ImaAdpcm::encodeSample(int16_t sample) {
    int32_t diff = sample - _predictedSample;
    uint8_t nibble = 0;
    int32_t step = STEP_TABLE[_stepIndex];

    if (diff < 0) {
        nibble = 8; // Set sign bit
        diff = -diff;
    }

    int32_t diffq = step >> 3;

    if (diff >= step) {
        nibble |= 4;
        diff -= step;
        diffq += step;
    }
    step >>= 1;

    if (diff >= step) {
        nibble |= 2;
        diff -= step;
        diffq += step;
    }
    step >>= 1;

    if (diff >= step) {
        nibble |= 1;
        diffq += step;
    }

    // Update predictor
    if (nibble & 8) {
        _predictedSample -= diffq;
    } else {
        _predictedSample += diffq;
    }

    // Clamp predicted sample to 16-bit signed range
    if (_predictedSample > 32767) _predictedSample = 32767;
    else if (_predictedSample < -32768) _predictedSample = -32768;

    // Update step index
    _stepIndex += INDEX_TABLE[nibble];
    if (_stepIndex < 0) _stepIndex = 0;
    else if (_stepIndex > 88) _stepIndex = 88;

    return (nibble & 0x0F);
}

int16_t ImaAdpcm::decodeNibble(uint8_t nibble) {
    int32_t step = STEP_TABLE[_stepIndex];
    int32_t diffq = step >> 3;

    if (nibble & 4) diffq += step;
    if (nibble & 2) diffq += (step >> 1);
    if (nibble & 1) diffq += (step >> 2);

    if (nibble & 8) {
        _predictedSample -= diffq;
    } else {
        _predictedSample += diffq;
    }

    if (_predictedSample > 32767) _predictedSample = 32767;
    else if (_predictedSample < -32768) _predictedSample = -32768;

    _stepIndex += INDEX_TABLE[nibble & 0x0F];
    if (_stepIndex < 0) _stepIndex = 0;
    else if (_stepIndex > 88) _stepIndex = 88;

    return _predictedSample;
}
