"""Import the artist-authored USDZs verbatim; never reconvert the legacy GLBs."""
from pathlib import Path
import shutil

source = Path.home() / 'Desktop/avatars/usdz'
target = Path(__file__).resolve().parents[1] / 'Cast/Assets/Characters'
for name in ['Iggy', 'Felipe', 'Todd', 'Alfred', 'Jojo']:
    shutil.copy2(source / f'{name}.usdz', target / f'{name}.usdz')
    print(f'Imported {name} unchanged')
