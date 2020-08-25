import os
from pathlib import Path

def print_sysimage(sysimage_path):
    print(f"\033[33;1;1m--- {sysimage_path.name}\033[m")
    with open(sysimage_path.joinpath("info.yml"), "r") as ifile:
        for line in ifile.readlines():
            print(line.strip("\n"))
        print("")

def get_available_sysimages(sysimages_path, **init_kwargs):
    sysimages = []
    for file in os.listdir(sysimages_path):
        filepath = sysimages_path.joinpath(file)
        if filepath.is_dir():
            if "sysimage.so" in os.listdir(filepath):
                sysimages.append(Sysimage(filepath.joinpath("sysimage.so"), **init_kwargs))
    return sysimages

def sizeof_fmt(num, suffix='B'):
    for unit in ['','Ki','Mi','Gi','Ti','Pi','Ei','Zi']:
        if abs(num) < 1024.0:
            return "%3.1f %s%s" % (num, unit, suffix)
        num /= 1024.0
    return "%.1f %s%s" % (num, 'Yi', suffix)

class Sysimage():
    def __init__(self, path: Path, color=True):
        self.path = path
        self.name = path.parent.name
        self.size = os.path.getsize(path)
        self._color = color

    def __str__(self):
        if self._color:
            return f"\033[36;1;1m{self.name:>10}\033[m (\033[32;1;1m{sizeof_fmt(self.size)}\033[m, {self.path})"
        else:
            return f"{self.name:>10} ({sizeof_fmt(self.size)}, {self.path})"


class SysimagesConfig():
    def __init__(self, sysimages_root: Path, **sysimage_init_kwargs):
        self.sysimages_root = sysimages_root
        self._sysimage_init_kwargs = sysimage_init_kwargs

    @property
    def sysimages(self):
        return get_available_sysimages(self.sysimages_root, **self._sysimage_init_kwargs)

    def print_sysimages(self):
        print("Available sysimages:")
        for sysimage in self.sysimages:
            print("   ", sysimage)

    def __str__(self):
        print(f"<{self.__class__.__name__} with {len(self.sysimages)} system images>")

def parse_cli():
    import argparse
    default_sysimages_path = Path.home().joinpath('.julia/sysimages')
    parser = argparse.ArgumentParser()
    parser.add_argument("sysimage_name", nargs="?", default="", help="optional sysimage name for which to give more detailed output")
    parser.add_argument('-s', '--sysimages-path', default=default_sysimages_path, type=Path, help=f"path where the sysimages are stored (defaults to {default_sysimages_path})")
    parser.add_argument('-n', '--no-color', action="store_true", help=f"disable color formatting during printing")
    args = parser.parse_args()
    return args.sysimage_name, args.sysimages_path, args.no_color

def main():
    sysimage_name, sysimages_path, no_color = parse_cli()
    if sysimage_name != "":
        print_sysimage(sysimages_path.joinpath(sysimage_name))

    sysimages_config = SysimagesConfig(sysimages_path, color=not(no_color))
    sysimages_config.print_sysimages()


if __name__ == '__main__':
    main()