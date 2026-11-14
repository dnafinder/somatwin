#!/usr/bin/env python3
"""Prepara assets/mh/body.bin dai dati MakeHuman (CC0, makehumancommunity/makehuman).

Uso: python3 tools/bake_mh.py <cartella makehuman/data> assets/mh/body.bin

Contenuto: mesh base del corpo (13380 vertici, quad triangolati) e i soli target
usati dall'app: macro caucasico per sesso ed eta', peso minimo e massimo (muscolo
medio), e le cinque circonferenze misurabili. Formato little-endian:
  'MHB1' | u32 nv | f32[nv*3] | u32 ntri | u16[ntri*3] | f32[3] asse polso |
  u32 nt | nt x ( u8 len | nome | u32 n | u16[n] indici | f32[n*3] delta )
"""
import struct, sys
import numpy as np

NV = 13380

def main(data, out):
    V = []; F = []; grp = None
    for line in open(data + '/3dobjs/base.obj'):
        if line.startswith('v '):
            V.append([float(x) for x in line.split()[1:4]])
        elif line.startswith('g '):
            grp = line.split()[1]
        elif line.startswith('f ') and grp == 'body':
            q = [int(t.split('/')[0]) - 1 for t in line.split()[1:]]
            F.append([q[0], q[1], q[2]]); F.append([q[0], q[2], q[3]])
    V = np.array(V[:NV], dtype='<f4'); F = np.array(F, dtype='<u2')
    names = []
    for g in ('male', 'female'):
        for a in ('young', 'old'):
            names.append(f'macrodetails/caucasian-{g}-{a}')
            for w in ('minweight', 'maxweight'):
                names.append(f'macrodetails/universal-{g}-{a}-averagemuscle-{w}')
    for n in ('neck-circ', 'waist-circ', 'hips-circ', 'calf-circ', 'wrist-circ'):
        for s in ('decr', 'incr'):
            names.append(f'measure/measure-{n}-{s}')
    axis = np.array([0.31, -0.54, 0.78], dtype='<f4'); axis /= np.linalg.norm(axis)
    with open(out, 'wb') as f:
        f.write(b'MHB1')
        f.write(struct.pack('<I', NV)); f.write(V.tobytes())
        f.write(struct.pack('<I', len(F))); f.write(F.tobytes())
        f.write(axis.astype('<f4').tobytes())
        f.write(struct.pack('<I', len(names)))
        for n in names:
            idx = []; d = []
            for line in open(f'{data}/targets/{n}.target'):
                if line.startswith('#') or not line.strip():
                    continue
                p = line.split(); i = int(p[0])
                if i < NV:
                    idx.append(i); d.append([float(p[1]), float(p[2]), float(p[3])])
            b = n.encode()
            f.write(struct.pack('<B', len(b))); f.write(b)
            f.write(struct.pack('<I', len(idx)))
            f.write(np.array(idx, dtype='<u2').tobytes())
            f.write(np.array(d, dtype='<f4').reshape(-1, 3).tobytes())

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
