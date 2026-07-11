(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

let md5 bytes = Digest.MD5.string bytes

let matches ~recorded bytes =
  String.equal recorded (Digest.MD5.string bytes)
  || String.equal recorded (Digest.BLAKE128.string bytes)

let admit ~recorded bytes =
  let md5 = Digest.MD5.string bytes in
  if
    String.equal recorded md5
    || String.equal recorded (Digest.BLAKE128.string bytes)
  then Some md5
  else None
