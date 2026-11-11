"""
00_get_data.py
Downloads the Olist Brazilian E-Commerce dataset from Kaggle straight into data/raw/
(no laptop download needed) and prints the size of every table.
Dataset: https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce  (licence: CC BY-NC-SA 4.0)
"""
import shutil
from pathlib import Path

import kagglehub
import pandas as pd

path = kagglehub.dataset_download("olistbr/brazilian-ecommerce")
raw = Path("data/raw")
raw.mkdir(parents=True, exist_ok=True)

print(f"{'file':<50}{'rows':>12}{'columns':>10}")
for f in sorted(Path(path).glob("*.csv")):
    shutil.copy(f, raw / f.name)
    df = pd.read_csv(raw / f.name)
    print(f"{f.name:<50}{len(df):>12,}{df.shape[1]:>10}")
print(f"\nSaved {len(list(raw.glob('*.csv')))} files to {raw}/")
