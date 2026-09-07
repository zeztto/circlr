#!/usr/bin/env python3
"""Build the macOS icon representations from the checked-in artwork."""
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile


def png_size(path):
    with path.open('rb') as source:
        header = source.read(24)
    if header[:16] != b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR':
        raise ValueError(f'Invalid PNG header: {path}')
    return struct.unpack('>II', header[16:24])


def replace_resource(path, data):
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix='.icon-', delete=False) as staged:
        staged_path = Path(staged.name)
        try:
            staged.write(data)
            staged.flush()
            staged_path.chmod(0o644)
            staged_path.replace(path)
        finally:
            staged_path.unlink(missing_ok=True)


def compile_catalog(temporary, source, resources):
    # A named Icon Composer asset avoids Tahoe's legacy icon framing.
    package = temporary / 'Circlr.icon'
    (package / 'Assets').mkdir(parents=True)
    shutil.copy2(resources / 'Brand/icon-composer.json', package / 'icon.json')
    shutil.copy2(source, package / 'Assets/circlr.png')
    output = temporary / 'compiled'
    output.mkdir()
    subprocess.run(['xcrun', 'actool', str(package), '--compile', str(output),
                    '--platform', 'macosx', '--minimum-deployment-target', '14.0',
                    '--app-icon', 'Circlr', '--output-partial-info-plist',
                    str(output / 'icon-info.plist')], check=True, stdout=subprocess.DEVNULL)
    data = (output / 'Assets.car').read_bytes()
    if len(data) < 8:
        raise ValueError('Empty compiled icon catalog')
    return data


def main():
    root = Path(__file__).resolve().parents[1]
    resources = root / 'Resources'
    source = resources / 'Brand/circlr-icon-v1.png'
    if png_size(source) != (1024, 1024):
        raise ValueError('App icon source must be 1024 x 1024 pixels')
    with tempfile.TemporaryDirectory(prefix='circlr-icon-') as temporary:
        iconset = Path(temporary) / 'AppIcon.iconset'
        iconset.mkdir()
        for size in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                suffix = '@2x' if scale == 2 else ''
                output = iconset / f'icon_{size}x{size}{suffix}.png'
                pixels = size * scale
                subprocess.run(['/usr/bin/sips', '-z', str(pixels), str(pixels),
                                str(source), '--out', str(output)],
                               check=True, stdout=subprocess.DEVNULL)
                if png_size(output) != (pixels, pixels):
                    raise ValueError(f'Incorrect icon dimensions: {output}')
        output = Path(temporary) / 'AppIcon.icns'
        subprocess.run(['/usr/bin/iconutil', '--convert', 'icns',
                        '--output', str(output), str(iconset)], check=True)
        data = output.read_bytes()
        if len(data) < 8 or data[:4] != b'icns' or struct.unpack('>I', data[4:8])[0] != len(data):
            raise ValueError('Invalid generated ICNS')
        catalog = compile_catalog(Path(temporary), source, resources)
        replace_resource(resources / 'AppIcon.icns', data)
        replace_resource(resources / 'Assets.car', catalog)
    print(resources / 'AppIcon.icns')


if __name__ == '__main__':
    main()
