import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Arrays;

public class TestHeaderParsing {

    public static byte[] packHeader(
        short magic, byte version, byte frameType, int fileId, int seqNum,
        int byteOffset, short payloadLen, short reserved, int totalFileSize,
        int chunkCrc32, int fileCrc32
    ) {
        ByteBuffer buf = ByteBuffer.allocate(32).order(ByteOrder.LITTLE_ENDIAN);
        buf.putShort(magic);          // 2B (0..2)
        buf.put(version);             // 1B (2..3)
        buf.put(frameType);           // 1B (3..4)
        buf.putInt(fileId);           // 4B (4..8)
        buf.putInt(seqNum);           // 4B (8..12)
        buf.putInt(byteOffset);       // 4B (12..16)
        buf.putShort(payloadLen);     // 2B (16..18)
        buf.putShort(reserved);       // 2B (18..20)
        buf.putInt(totalFileSize);    // 4B (20..24)
        buf.putInt(chunkCrc32);       // 4B (24..28)
        buf.putInt(fileCrc32);        // 4B (28..32)
        return buf.array();
    }

    public static void testUnpackExactKotlinLogic() {
        System.out.println(=== Test 1.1: Exact Kotlin 32-Byte Header Unpacking ===);
        
        short expMagic = (short)0xAA55;
        byte expVersion = 0x01;
        byte expFrameType = 0x01;
        int expFileId = 1048576;
        int expSeqNum = 42;
        int expByteOffset = 21504;
        short expPayloadLen = 512;
        short expReserved = 0;
        int expTotalFileSize = (int)16777216L; // 16 MB
        int expChunkCrc32 = (int)0xDEADBEEFL;
        int expFileCrc32 = (int)0xCAFEBABEL;

        byte[] rawBytes = packHeader(
            expMagic, expVersion, expFrameType, expFileId, expSeqNum,
            expByteOffset, expPayloadLen, expReserved, expTotalFileSize,
            expChunkCrc32, expFileCrc32
        );

        if (rawBytes.length != 32) {
            throw new RuntimeException(Header byte array length is  + rawBytes.length + , expected 32);
        }

        // Exact Kotlin unpacking code from BleL2capAudioReceiver.kt
        ByteBuffer headerBuffer = ByteBuffer.allocate(32).order(ByteOrder.LITTLE_ENDIAN);
        headerBuffer.put(rawBytes);
        headerBuffer.position(0);

        int magic = headerBuffer.getShort() & 0xFFFF;
        byte version = headerBuffer.get();
        byte frameType = headerBuffer.get();
        int fileId = headerBuffer.getInt();
        int seqNum = headerBuffer.getInt();
        int byteOffset = headerBuffer.getInt();
        int payloadLen = headerBuffer.getShort() & 0xFFFF;
        short reserved = headerBuffer.getShort();
        long totalFileSize = headerBuffer.getInt() & 0xFFFFFFFFL;
        long chunkCrc32 = headerBuffer.getInt() & 0xFFFFFFFFL;
        long expectedFileCrc32 = headerBuffer.getInt() & 0xFFFFFFFFL;

        System.out.printf(Parsed: magic=0x%04X, ver=%d, type=%d, fileId=%d, seq=%d, offset=%d, payloadLen=%d, totalSize=%d, chunkCrc=0x%08X, fileCrc=0x%08X\n,
            magic, version, frameType, fileId, seqNum, byteOffset, payloadLen, totalFileSize, chunkCrc32, expectedFileCrc32);

        assert magic == 0xAA55 : Magic mismatch;
        assert version == expVersion : Version mismatch;
        assert frameType == expFrameType : FrameType mismatch;
        assert fileId == expFileId : FileId mismatch;
        assert seqNum == expSeqNum : SeqNum mismatch;
        assert byteOffset == expByteOffset : ByteOffset mismatch;
        assert payloadLen == (expPayloadLen & 0xFFFF) : PayloadLen mismatch;
        assert reserved == expReserved : Reserved mismatch;
        assert totalFileSize == (expTotalFileSize & 0xFFFFFFFFL) : TotalFileSize mismatch;
        assert chunkCrc32 == 0xDEADBEEFL : ChunkCrc32 mismatch;
        assert expectedFileCrc32 == 0xCAFEBABEL : FileCrc32 mismatch;
        assert headerBuffer.position() == 32 : Position should be exactly 32;
        assert headerBuffer.remaining() == 0 : Buffer should have 0 remaining bytes;

        System.out.println(-> PASS: All 11 fields unpacked correctly at exact byte positions without underflow!);
    }

    public static void testBufferUnderflowBugReproduction() {
        System.out.println(\n=== Test 1.2: Reproducing Legacy 30-Byte Underflow Bug ===);
        byte[] rawBytes = packHeader(
            (short)0xAA55, (byte)1, (byte)1, 1, 1, 0, (short)512, (short)0, 1024, 0x12345678, 0x9ABCDEF0
        );

        ByteBuffer buf30 = ByteBuffer.allocate(30).order(ByteOrder.LITTLE_ENDIAN);
        buf30.put(rawBytes, 0, 30);
        buf30.position(0);

        try {
            int magic = buf30.getShort() & 0xFFFF;
            byte version = buf30.get();
            byte frameType = buf30.get();
            int fileId = buf30.getInt();
            int seqNum = buf30.getInt();
            int byteOffset = buf30.getInt();
            int payloadLen = buf30.getShort() & 0xFFFF;
            short reserved = buf30.getShort();
            long totalFileSize = buf30.getInt() & 0xFFFFFFFFL;
            long chunkCrc32 = buf30.getInt() & 0xFFFFFFFFL;
            long expectedFileCrc32 = buf30.getInt() & 0xFFFFFFFFL; // Should throw!
            System.err.println(-> FAIL: Expected BufferUnderflowException but succeeded!);
        } catch (java.nio.BufferUnderflowException e) {
            System.out.println(-> CONFIRMED: 30-byte buffer triggers java.nio.BufferUnderflowException when reading expectedFileCrc32. 32-byte fix is mandatory.);
        }
    }

    public static void main(String[] args) {
        testUnpackExactKotlinLogic();
        testBufferUnderflowBugReproduction();
    }
}
