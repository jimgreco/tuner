import urllib.request, urllib.parse, re, concurrent.futures
from pathlib import Path
import subprocess, tempfile

root = Path(__file__).resolve().parents[1]
cache = Path(tempfile.gettempdir()) / "tuner-recordings"
cache.mkdir(exist_ok=True)
url='https://theremin.music.uiowa.edu/MISguitar.html'
html=urllib.request.urlopen(url).read().decode()
names=['Guitar.mf.sulE.E2B2.mono.aif','Guitar.mf.sulA.A2B2.mono.aif','Guitar.mf.sulD.D3B3.mono.aif','Guitar.mf.sulG.G3B3.mono.aif','Guitar.mf.sulB.B3.mono.aif','Guitar.mf.sul_E.E4B4.mono.aif']
links=re.findall(r'href=[\"\']([^\"\']+)',html,re.I)
def fetch(name):
 link=next(l for l in links if l.endswith(name))
 remote=urllib.parse.quote(urllib.parse.urljoin(url,link), safe=":/%")
 path=cache / name
 if not path.exists():
  with urllib.request.urlopen(remote, timeout=60) as response:
   data = response.read()
  path.write_bytes(data)
 return name,remote
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
 for result in executor.map(fetch,names):print(*result)

subprocess.run(["swiftc", "-O", str(root / "Tuner/TuningMath.swift"), str(root / "Scripts/ValidateRecordings.swift"), "-o", str(cache / "validate")], check=True)
subprocess.run([str(cache / "validate"), str(cache)], check=True)
