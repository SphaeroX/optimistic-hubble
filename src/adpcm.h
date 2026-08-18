#pragma once
#include <Arduino.h>

class ImaAdpcm {
public:
    ImaAdpcm();

    void reset();
    uint8_t encodeSample(int16_t sample);
    int16_t decodeNibble(uint8_t nibble);

    int16_t getPredictedSample() const { return _predictedSample; }
    int8_t getStepIndex() const { return _stepIndex; }

private:
    int16_t _predictedSample;
    int8_t _stepIndex;

    static const int16_t STEP_TABLE[89];
    static const int8_t INDEX_TABLE[16];
};
