import struct
import zlib
import io

def simulate_l2cap_stream():
    # Construct a test audio payload (e.g. 1000 bytes)
    audio_data = bytes([i % 256 for i in range(1000)])
    file_id = 101
    total_size = len(audio_data)
    file_crc = zlib.crc32(audio_data)

    # Chunk into 512-byte blocks
    chunk_size = 512
    stream_bytes = bytearray()

    seq = 0
    offset = 0
    while offset < total_size:
        curr_len = min(chunk_size, total_size - offset)
        payload = audio_data[offset:offset+curr_len]
        chunk_crc = zlib.crc32(payload)

        # Pack 32-byte header
        # uint16_t magic (0xAA55)
        # uint8_t version (1)
        # uint8_t frameType (1 = DATA)
        # uint32_t fileId (file_id)
        # uint32_t sequenceNum (seq)
        # uint32_t byteOffset (offset)
        # uint16_t payloadLength (curr_len)
        # uint16_t reserved (0)
        # uint32_t totalFileSize (total_size)
        # uint32_t chunkCrc32 (chunk_crc)
        # uint32_t fileCrc32 (file_crc)
        header = struct.pack("<HBBIIIHHIII", 0xAA55, 1, 1, file_id, seq, offset, curr_len, 0, total_size, chunk_crc, file_crc)
        assert len(header) == 32
        stream_bytes.extend(header)
        stream_bytes.extend(payload)
        seq += 1
        offset += curr_len

    # Add FIN frame
    fin_header = struct.pack("<HBBIIIHHIII", 0xAA55, 1, 5, file_id, seq, offset, 0, 0, total_size, 0, file_crc)
    stream_bytes.extend(fin_header)

    # Now simulate Kotlin parsing
    inp = io.BytesIO(stream_bytes)
    received_audio = bytearray()
    running_crc = 0

    while True:
        header_buf = inp.read(32)
        if not header_buf or len(header_buf) < 32:
            break
        magic, ver, ftype, fid, snum, boff, plen, res, tot_sz, c_crc, exp_fcrc = struct.unpack("<HBBIIIHHIII", header_buf)
        assert magic == 0xAA55
        if ftype == 5:
            print("FIN frame received!")
            break
        payload = inp.read(plen)
        assert len(payload) == plen
        calc_ccrc = zlib.crc32(payload)
        assert calc_ccrc == c_crc, f"Chunk CRC mismatch: {calc_ccrc} vs {c_crc}"
        received_audio.extend(payload)

    final_crc = zlib.crc32(received_audio)
    assert received_audio == audio_data
    assert final_crc == file_crc
    print(f"Simulation verified: {len(received_audio)} bytes received, CRC 0x{final_crc:08X} matches!")

if __name__ == "__main__":
    simulate_l2cap_stream()
