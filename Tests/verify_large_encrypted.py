"""Independently verify the opt-in Swift >4GiB fixture with Python's standard library."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile


def stream_hash(file):
    digest = hashlib.sha256()
    while chunk := file.read(1024 * 1024):
        digest.update(chunk)
    return digest.hexdigest()


def file_hash(path):
    with path.open('rb') as file:
        return stream_hash(file)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path, help='Swift large-encrypted test report.json')
    args = parser.parse_args()
    report = json.loads(args.report.read_text())
    assert report['status'] == 'passed'
    pages = report['encrypted_pages']
    encrypted_size = report['encrypted_size']
    binary_size = report['binary_size']
    assert encrypted_size == pages * 4096
    assert binary_size > 2**32 and binary_size == 4096 + encrypted_size + 8192
    assert encrypted_size == (2**32 - 1) // 4096 * 4096

    # Construct expected plaintext without using Swift's fixture bytes or cryptographic implementation.
    header = struct.pack('<14I', 0xfeedfacf, 0x0100000c, 0, 2, 1, 24, 0, 0,
                         0x2c, 24, 4096, encrypted_size, 0, 0)
    expected = hashlib.sha256(header + bytes(4096 - len(header)))
    pattern = bytes(range(256)) * 16
    for start in range(0, pages, 4096):
        count = min(4096, pages - start)
        block = bytearray(pattern * count)
        for index in range(count):
            struct.pack_into('<Q', block, index * 4096, start + index)
        expected.update(block)
    expected.update(bytes([0x5a]) * 8192)
    expected_hash = expected.hexdigest()
    assert expected_hash == report['expected_plaintext_sha256']

    binary_path = 'Payload/Large.app/Large'
    result = {'status': 'passed', 'binary_size': binary_size, 'encrypted_size': encrypted_size,
              'encrypted_pages': pages, 'independent_expected_plaintext_sha256': expected_hash, 'modes': []}
    with zipfile.ZipFile(report['input']) as original:
        with original.open(binary_path) as file:
            assert stream_hash(file) == report['expected_ciphertext_sha256']
        for mode in report['modes']:
            output = Path(mode['output'])
            with zipfile.ZipFile(output) as archive:
                assert archive.namelist() == original.namelist()
                assert archive.comment == original.comment
                entry = archive.getinfo(binary_path)
                assert entry.file_size == binary_size and entry.extract_version >= 45
                with archive.open(binary_path) as file:
                    header = file.read(56)
                    assert struct.unpack_from('<I', header, 48)[0] == 0
                    assert struct.unpack_from('<I', header, 44)[0] == encrypted_size
                with archive.open(binary_path) as file:
                    digest = stream_hash(file)  # ZipExtFile also verifies CRC on reaching EOF.
                assert digest == expected_hash == mode['binary_sha256']
                for item in archive.infolist():
                    before = original.getinfo(item.filename)
                    for key in ['extra', 'comment', 'external_attr', 'internal_attr', 'create_system',
                                'create_version', 'extract_version', 'date_time', 'flag_bits', 'compress_type',
                                'file_size', 'compress_size', 'header_offset']:
                        assert getattr(item, key) == getattr(before, key), (item.filename, key)
                    if item.filename != binary_path:
                        assert archive.read(item) == original.read(before)
            metrics = {}
            for line in Path(mode['time_log']).read_text().splitlines():
                for label, key in [('maximum resident set size', 'maximum_resident_bytes'),
                                   ('peak memory footprint', 'peak_memory_footprint_bytes')]:
                    if line.strip().endswith(label):
                        metrics[key] = int(line.split()[0])
            result['modes'].append({'mode': mode['mode'], 'seconds': mode['seconds'],
                                    'binary_sha256': digest, 'archive_sha256': file_hash(output),
                                    'python_zip_crc_verified': True, 'metadata_verified': True, **metrics})
    assert {mode['mode'] for mode in result['modes']} == {'lowmem', 'fast'}
    assert len({mode['archive_sha256'] for mode in result['modes']}) == 1
    result['output_archives_byte_identical'] = True
    destination = args.report.with_name('independent-verification.json')
    destination.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
