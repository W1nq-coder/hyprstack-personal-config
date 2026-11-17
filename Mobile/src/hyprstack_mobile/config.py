"""Validate persisted preferences before they reach GTK/path APIs."""
import json


def load(path):
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        return {}
    if not isinstance(data, dict):
        return {}
    result = {k: data[k] for k in ('light', 'reduce_motion') if type(data.get(k)) is bool}
    if isinstance(data.get('wallpaper'), str):
        result['wallpaper'] = data['wallpaper']
    favorites = data.get('favorites', [])
    if isinstance(favorites, list):
        result['favorites'] = list(dict.fromkeys(x for x in favorites if isinstance(x, str) and x))
    return result
