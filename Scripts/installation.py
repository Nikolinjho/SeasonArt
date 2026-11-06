#!/usr/bin/env python3
"""Личная установка SeasonArt с фиксированным путём назначения."""
import ctypes
import datetime
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import uuid

BUNDLE_ID = 'dev.nikoko.SeasonArt'
ROOT = Path(__file__).resolve().parents[1]
LSREGISTER = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'


def no_symlinks(path):
    path = Path(os.path.abspath(path))
    if any(part.is_symlink() for part in (path, *path.parents)):
        raise ValueError(f'Symlink paths are not allowed: {path}')
    return path


def rollback_source(candidate, backups):
    candidate = Path(candidate)
    if '..' in candidate.parts:
        raise ValueError('Rollback traversal is not allowed')
    candidate = no_symlinks(candidate)
    backups = no_symlinks(backups)
    if candidate.parent.parent != backups or candidate.name != 'SeasonArt.app' or not candidate.is_dir():
        raise ValueError('Choose an existing build/backups/<timestamp>/SeasonArt.app')
    return candidate


def validate_bundle(bundle):
    bundle = no_symlinks(bundle)
    with (bundle / 'Contents' / 'Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    if info.get('CFBundleIdentifier') != BUNDLE_ID:
        raise ValueError('Unexpected bundle identifier')
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(bundle)], check=True)
    # Проверяем не только plist, но и идентификатор, закреплённый подписью.
    subprocess.run(['/usr/bin/codesign', '--verify', '--strict', '-R',
                    f'=identifier "{BUNDLE_ID}"', str(bundle)], check=True)
    details = subprocess.run(['/usr/bin/codesign', '-d', '--verbose=4', str(bundle)],
                             check=True, capture_output=True, text=True)
    if 'Signature=adhoc' in details.stderr or 'Authority=' not in details.stderr:
        raise ValueError('A certificate-signed bundle is required')


def atomic_exchange(left, right):
    library = ctypes.CDLL(None, use_errno=True)
    rename = library.renameatx_np
    rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    if rename(-2, os.fsencode(left), -2, os.fsencode(right), 2) != 0:  # AT_FDCWD, RENAME_SWAP
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))


def install(source, destination, backups, *, validate=validate_bundle, stop,
            register, copy=shutil.copytree, exchange=atomic_exchange):
    source, destination, backups = map(no_symlinks, (source, destination, backups))
    validate(source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    staging_directory = Path(tempfile.mkdtemp(prefix='.SeasonArt-install-', dir=destination.parent))
    staged = staging_directory / 'SeasonArt.app'
    backup = None
    swapped = False
    restore_failed = False
    existed = destination.exists()
    try:
        copy(source, staged)
        validate(staged)
        if existed:
            validate(destination)
            stamp = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=3))).strftime('%Y%m%d-%H%M%S-MSK')
            backup_directory = backups / (stamp + '-' + uuid.uuid4().hex[:8])
            backup_directory.mkdir(parents=True, exist_ok=False)
            backup = backup_directory / 'SeasonArt.app'
            copy(destination, backup)
            validate(backup)
        stop()
        if existed:
            exchange(staged, destination)
        else:
            os.rename(staged, destination)
        swapped = True
        validate(destination)
        register(destination)
    except BaseException:
        if swapped:
            try:
                if existed:
                    exchange(staged, destination)
                else:
                    os.rename(destination, staged)
            except BaseException as restore_error:
                restore_failed = True
                # Сохраняем прежний бандл рядом с назначением и резервную копию для восстановления.
                raise RuntimeError(f'Automatic restore failed; preserve {staging_directory} and {backup}') from restore_error
        raise
    finally:
        if not restore_failed:
            shutil.rmtree(staging_directory)
    return backup


def stop_application():
    subprocess.run(['/usr/bin/swift', str(ROOT / 'Scripts' / 'stop-seasonart.swift')], check=True)


def register_application(destination):
    subprocess.run([LSREGISTER, '-f', str(destination)], check=True)


def launch_application(destination, *, run=subprocess.run):
    try:
        run(['/usr/bin/open', '-g', str(destination)], check=True, capture_output=True, text=True)
    except (OSError, subprocess.SubprocessError) as error:
        detail = getattr(error, 'stderr', None) or str(error)
        raise RuntimeError(f'Приложение установлено, но не запущено: {detail.strip()}') from error


def main(arguments):
    if not arguments or arguments[0] not in ('install', 'rollback'):
        raise ValueError('Usage: install.sh | rollback.sh build/backups/<timestamp>/SeasonArt.app')
    mode = arguments[0]
    backups = ROOT / 'build' / 'backups'
    if mode == 'install' and len(arguments) == 1:
        source = ROOT / 'build' / 'SeasonArt.app'
    elif mode == 'rollback' and len(arguments) == 2:
        source = rollback_source(Path(arguments[1]), backups)
    else:
        raise ValueError('No destination override is supported')
    destination = Path.home() / 'Applications' / 'SeasonArt.app'
    backup = install(source, destination, backups, stop=stop_application, register=register_application)
    # Сборка остаётся на диске, но больше не конкурирует с установленным приложением в LaunchServices.
    build_product = ROOT / 'build' / 'SeasonArt.app'
    result = subprocess.run([LSREGISTER, '-u', str(build_product)], capture_output=True, text=True)
    if result.returncode:
        print('Warning: build-product LaunchServices unregistration failed.', file=sys.stderr)
    print(f'Installed: {destination}')
    if backup:
        print(f'Backup: {backup}')
    launch_application(destination)


if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except (ValueError, OSError, subprocess.SubprocessError, RuntimeError) as error:
        print(f'SeasonArt: {error}', file=sys.stderr)
        sys.exit(1)
