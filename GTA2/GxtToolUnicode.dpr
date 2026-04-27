program GxtToolUnicode;

{
  GXT<=>TXT converter for GTA2
  by Daniel Marschall
  Revision: 27 April 2026
  Licensed under the terms of the Apache 2.0 license
  Source code compatible with Delphi for Win32/64, and FreePascal for Debian Linux
  More information here: https://misc.daniel-marschall.de/spiele/gta2/
}

{$IFDEF FPC}
  {$mode delphi}
  {$H+}
{$ELSE}
  {$APPTYPE CONSOLE}

{$ENDIF}

{$IFDEF FPC}
uses
  SysUtils,
  Classes,
  baseunix,
  ctypes;
{$ELSE}
{$R *.dres}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  WinApi.Windows;

{$ENDIF}

resourcestring
  S_INVALID_PARAM = 'Invalid parameter/file';
  S_INVALID_FILE = 'File is neither TXT nor GXT';
  S_ERR_S_S = 'ERROR (%s): %s';
  S_WARN_S_S = 'WARNING (%s): %s';
  S_OK_S_S_LANG_S = 'OK: %s => %s (Language: %s)';
  {$IFDEF MSWINDOWS}
  S_PRESS_ANY_KEY = 'Press any key to exit.';
  {$ENDIF}
  S_INTRO_1 = 'GXT<>TXT Converter for GTA 2 (Unicode Version)';
  S_INTRO_2 = 'by Daniel Marschall';
  S_INTRO_3 = 'Revision: 27 April 2026';
  S_INTRO_4 = 'Licensed under the terms of the Apache 2.0 license';
  S_USAGE = 'Usage:';
  S_IllegalKanji = 'Warning: Illegal character not in Kanji.dat: %s';
  S_IllegalEuropeanChar = 'Warning: Illegal European character: %s';
  S_ENTER_LANGUAGE = 'Please enter the language of %s (E,G,F,I,S,R,J)';
  SInvalidLineIgnored = 'Attention: Invalid line was ignored: %s';
  SInvalidLine = 'Error: Invalid line: %s';
  SLineTooLongIgnored = 'Attention: Line was ignored because key was too long: %s';
  SUnknownSectionType_S = 'Attention: Unknown section type "%s"';
  SWarnExtraBytes = 'Attention: %d extra bytes at end of file.';
  SSectionNotFound = 'ERROR: Section "%s" not found';
  SMagicHeaderMissing = 'ERROR: Magic header "%s" missing.';
  SLanguageMustBe_S = 'ERROR: Language must be "%s".';
  SWrongFileVersion = 'ERROR: %s version doesn''t have the value %d.';
  SFileNotFound = 'File not found: %s';

// --- GTA2 Specific

const
  GXT_MAGIC = 'GBL';
  GXT_VER = 100;
  KAN_MAGIC = 'KAN';
  KAN_VER = 100;

  MAX_KEY_SIZE = 8;
  EU_Charset_Convert: array[0..48,0..1] of AnsiChar = (
        (#$80, #$C0),
        (#$81, #$C1),
        (#$82, #$C2),
        (#$83, #$C4),
        (#$84, #$C6),
        (#$85, #$C7),
        (#$86, #$C8),
        (#$87, #$C9),
        (#$88, #$CA),
        (#$89, #$CB),
        (#$8A, #$CC),
        (#$8B, #$CD),
        (#$8C, #$CE),
        (#$8D, #$CF),
        (#$8E, #$D2),
        (#$8F, #$D3),
        (#$90, #$D4),
        (#$91, #$D6),
        (#$92, #$D9),
        (#$93, #$DA),
        (#$94, #$DB),
        (#$95, #$DC),
        (#$96, #$DF),
        (#$97, #$E0),
        (#$98, #$E1),
        (#$99, #$E2),
        (#$9A, #$E4),
        (#$9B, #$E6),
        (#$9C, #$E7),
        (#$9D, #$E8),
        (#$9E, #$E9),
        (#$9F, #$EA),
        (#$A0, #$EB),
        (#$A1, #$EC),
        (#$A2, #$ED),
        (#$A3, #$EE),
        (#$A4, #$EF),
        (#$A5, #$F2),
        (#$A6, #$F3),
        (#$A7, #$F4),
        (#$A8, #$F6),
        (#$A9, #$F9),
        (#$AA, #$FA),
        (#$AB, #$FB),
        (#$AC, #$FC),
        (#$AD, #$D1),
        (#$AE, #$F1),
        (#$AF, #$BF),
        (#$B0, #$A1)
  );

type
  TGTA2Header = packed record
    magic: array[0..2] of AnsiChar; // "GBL" (*.gxt), "KAN" (kanji.dat)
    lang: AnsiChar; // E,G,F,I,S,R,J
    version: word // always 64 00 = 100
  end;

  TGTA2SectionHeader = packed record
    sectionKey: array[0..3] of AnsiChar; // TKEY/TDAT (*.gxt), KIDX/KBIT (kanji.dat)
    sectionLength: Cardinal;
  end;

  TKEYEntry = packed record
    relDataOffset: Cardinal;
    key: array[0..MAX_KEY_SIZE-1] of AnsiChar;
  end;

  TGTAMessage = record
    key: AnsiString;
    guy: AnsiChar;
    msg: WideString;
  end;
  TGTAMessagesArray = array of TGTAMessage;

// --- Encoding Stuff

const
  CP_UTF8 = 65001;
  CP_EURO = 1252;
  CP_SJIS = 932;

function MakeEncoding(CodePage: Integer): TEncoding;
begin
  Result := TEncoding.GetEncoding(CodePage);
end;

function BytesToRawString(const B: TBytes): RawByteString;
begin
  if Length(B) > 0 then
    SetString(Result, PAnsiChar(@B[0]), Length(B))
  else
    Result := '';
end;

function RawByteStringToBytes(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if Length(S) > 0 then
    Move(PAnsiChar(S)^, Result[0], Length(S));
end;

{$IFDEF FPC}
type
  iconv_t = Pointer;

function iconv_open(tocode, fromcode: PChar): iconv_t; cdecl; external 'c';
function iconv(cd: iconv_t; inbuf: PPChar; inbytesleft: PSizeUInt; outbuf: PPChar; outbytesleft: PSizeUInt): SizeUInt; cdecl; external 'c';
function iconv_close(cd: iconv_t): cint; cdecl; external 'c';

function ConvertWithIconv(const Data: TBytes; SourceEncoding, TargetEncoding: TEncoding): TBytes;

  function EncodingToIconvName(Enc: TEncoding): string;
  begin
    if Enc.CodePage = CP_UTF8 then Exit('UTF-8');
    if Enc.CodePage = CP_SJIS then Exit('CP932');
    if Enc.CodePage = CP_EURO then Exit('CP1252');
    raise Exception.Create('Unsupported encoding: ' + IntToStr(Enc.CodePage));
  end;

var
  cd: iconv_t;
  InBuf, OutBuf: PAnsiChar;
  InBytesLeft, OutBytesLeft: SizeUInt;
  OutSize: SizeUInt;
  PIn, POut: PAnsiChar;
  FromEnc, ToEnc: string;
begin
  Result := nil;

  FromEnc := EncodingToIconvName(SourceEncoding);
  ToEnc := EncodingToIconvName(TargetEncoding);

  cd := iconv_open(PChar(ToEnc), PChar(FromEnc));
  if cd = iconv_t(-1) then
    raise Exception.Create('iconv_open failed');

  try
    InBytesLeft := Length(Data);
    OutSize := InBytesLeft * 4 + 16;

    SetLength(Result, OutSize);

    PIn := PAnsiChar(@Data[0]);
    POut := PAnsiChar(@Result[0]);

    InBuf := PIn;
    OutBuf := POut;
    OutBytesLeft := OutSize;

    while InBytesLeft > 0 do
    begin
      if iconv(cd, @InBuf, @InBytesLeft, @OutBuf, @OutBytesLeft) = SizeUInt(-1) then
        raise Exception.Create('iconv failed. File has probably invalid characters.');
    end;

    SetLength(Result, OutSize - OutBytesLeft);
  finally
    iconv_close(cd);
  end;
end;
{$ENDIF}

// --- Read File Methods

function ReadAllBytesFromFile(const FileName: string): TBytes;
{$IFDEF FPC}
var
  FS: TFileStream;
begin
  Result := nil; // SetLength(Result, 0);
  if not FileExists(FileName) then
    raise Exception.CreateFmt(SFileNotFound, [FileName]);

  FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, FS.Size);
    if FS.Size > 0 then
      FS.ReadBuffer(Result[0], FS.Size);
  finally
    FreeAndNil(FS);
  end;
{$ELSE}
begin
  Result := TFile.ReadAllBytes(FileName);
{$ENDIF}
end;

function ReadTextFileWithEncoding(const FileName: string; const SourceEncoding: TEncoding; const TargetEncoding: TEncoding): TBytes;
{$IFDEF FPC}

  function RemovePreamble(const Bytes: TBytes; const Encoding: TEncoding): TBytes;
  var
    Preamble: TBytes;
    I: Integer;
    Matches: Boolean;
  begin
    Result := Bytes;
    Preamble := Encoding.GetPreamble;
    if Length(Preamble) = 0 then
      Exit;
    if Length(Bytes) < Length(Preamble) then
      Exit;
    Matches := True;
    for I := 0 to High(Preamble) do
    begin
      if Bytes[I] <> Preamble[I] then
      begin
        Matches := False;
        Break;
      end;
    end;
    if Matches then
      Result := Copy(Bytes, Length(Preamble), Length(Bytes) - Length(Preamble));
  end;

var
  B: TBytes;
begin
  B := ReadAllBytesFromFile(FileName);
  B := RemovePreamble(B, SourceEncoding);
  Result := ConvertWithIconv(B, SourceEncoding, TargetEncoding);

{$ELSE}
begin
  Result := TargetEncoding.GetBytes(TFile.ReadAllText(FileName, SourceEncoding));
{$ENDIF}
end;

// --- File Detection

type
  TFileEncInfo = record
    IsUtf8: Boolean;
    IsJapanese: Boolean;
    Encoding: TEncoding;
    FileEncoding: TEncoding; // for reading the file
  end;

// Decode UTF-8 sequence and check for CJK (U+3000..U+9FFF, U+F900..U+FAFF)
function IsCJKCodepoint(CP: Cardinal): Boolean;
begin
  Result := ((CP >= $3000) and (CP <= $9FFF)) or
            ((CP >= $F900) and (CP <= $FAFF));
end;

function DetectFileEncoding(const FileName: string): TFileEncInfo;
var
  RawBytes, Sample: TBytes;
  I: Integer;
  HasBOM, IsShiftJIS, HasCJK: Boolean;
  B, B2: Byte;
  CodePoint: Cardinal;
  SJISBytes: Integer;
begin
  Result.IsUtf8 := False;
  Result.IsJapanese := False;
  Result.Encoding := MakeEncoding(CP_EURO);
  Result.FileEncoding := MakeEncoding(CP_EURO);

  RawBytes := ReadAllBytesFromFile(FileName);
  if Length(RawBytes) = 0 then
    Exit;

  // Sample: First 8 KB is enough for heuristics
  if Length(RawBytes) < 8192 then
    SetLength(Sample, Length(RawBytes))
  else
    SetLength(Sample, 8192);
  Move(RawBytes[0], Sample[0], Length(Sample));

  // --- 1. Check BOM ---
  HasBOM := (Length(Sample) >= 3) and
            (Sample[0] = $EF) and (Sample[1] = $BB) and (Sample[2] = $BF);

  if HasBOM then
  begin
    // UTF-8 with BOM: Check contents for CJK
    Result.IsUtf8 := True;
    HasCJK := False;
    I := 3;
    while I < Length(Sample) - 2 do
    begin
      B := Sample[I];
      // 3-Byte UTF-8: $E3..$E9 → CJK-Area
      if (B >= $E3) and (B <= $E9) and
         ((Sample[I+1] and $C0) = $80) and
         ((Sample[I+2] and $C0) = $80) then
      begin
        CodePoint := ((Cardinal(B) and $0F) shl 12) or
                     ((Cardinal(Sample[I+1]) and $3F) shl 6) or
                      (Cardinal(Sample[I+2]) and $3F);
        if IsCJKCodepoint(CodePoint) then
        begin
          HasCJK := True;
          Break;
        end;
      end;
      Inc(I);
    end;
    Result.IsJapanese := HasCJK;
    Result.FileEncoding := MakeEncoding(CP_UTF8);
    if HasCJK then
      Result.Encoding := MakeEncoding(CP_SJIS)
    else
      Result.Encoding := MakeEncoding(CP_EURO);
    Exit;
  end;

  // --- 2. Detect Shift-JIS ---
  // Shift-JIS Lead-Bytes: $81-$9F or $E0-$EF, Trail: $40-$FC (except $7F)
  SJISBytes := 0;
  I := 0;
  while I < Length(Sample) - 1 do
  begin
    B := Sample[I];
    B2 := Sample[I + 1];
    if (((B >= $81) and (B <= $9F)) or ((B >= $E0) and (B <= $EF))) and
       ((B2 >= $40) and (B2 <= $FC) and (B2 <> $7F)) then
    begin
      Inc(SJISBytes, 2);
      Inc(I); // Skip second byte
    end;
    Inc(I);
  end;

  IsShiftJIS := (SJISBytes > Length(Sample) div 5); // >20%

  if IsShiftJIS then
  begin
    Result.IsJapanese := True;
    Result.Encoding := MakeEncoding(CP_SJIS);
    Result.FileEncoding := MakeEncoding(CP_SJIS);
    Exit;
  end;

  // --- 3. Detect UTF-8 without BOM ---
  Result.IsUtf8 := False;
  HasCJK := False;
  I := 0;
  while I < Length(Sample) - 2 do
  begin
    B := Sample[I];
    // 2-Byte: $C2-$DF
    if (B >= $C2) and (B <= $DF) and ((Sample[I+1] and $C0) = $80) then
    begin
      Result.IsUtf8 := True;
      Inc(I, 2);
      Continue;
    end;
    // 3-Byte: $E0-$EF → check for CJK
    if (B >= $E0) and (B <= $EF) and
       ((Sample[I+1] and $C0) = $80) and
       ((Sample[I+2] and $C0) = $80) then
    begin
      Result.IsUtf8 := True;
      CodePoint := ((Cardinal(B) and $0F) shl 12) or
                   ((Cardinal(Sample[I+1]) and $3F) shl 6) or
                    (Cardinal(Sample[I+2]) and $3F);
      if IsCJKCodepoint(CodePoint) then
        HasCJK := True;
      Inc(I, 3);
      Continue;
    end;
    Inc(I);
  end;

  if Result.IsUtf8 then
  begin
    Result.IsJapanese := HasCJK;
    Result.FileEncoding := MakeEncoding(CP_UTF8);
    if HasCJK then
      Result.Encoding := MakeEncoding(CP_SJIS)
    else
      Result.Encoding := MakeEncoding(CP_EURO);
    Exit;
  end;

  // --- 4. ANSI Fallback: only Byte-Statistics ---
  // Middle European ANSI: $80-$FF without Shift-JIS-Pattern → CP1252
  // (IsJapanese stays False, Encoding stays 1252)
end;

// --- Japanese Kanji Methods

function LoadKanjiDat: TBytes;

  function ParseKanjiDat(fs: TStream): TBytes;
  var
    filHead: TGTA2Header;
    secHead: TGTA2SectionHeader;
    extra: integer;
  begin
    fs.Position := 0;

    fs.Read(filHead, SizeOf(filHead));

    // Optional checks
    if filHead.magic <> KAN_MAGIC then
      raise Exception.CreateFmt(SMagicHeaderMissing, [KAN_MAGIC]);
    if filHead.lang <> 'J' then // do not localize
      raise Exception.CreateFmt(SLanguageMustBe_S, ['J']); // do not localize
    if filHead.version <> KAN_VER then
      raise Exception.CreateFmt(SWrongFileVersion, [KAN_MAGIC, KAN_VER]);
    fs.Seek(SizeOf(filHead), soFromBeginning);
    while fs.Position < fs.Size do
    begin
      fs.Read(secHead, SizeOf(secHead));
      if (secHead.sectionKey <> 'KIDX') and (secHead.sectionKey <> 'KBIT') then // do not localize
        WriteLn(Format(SUnknownSectionType_S, [secHead.sectionKey]));
      fs.Seek(secHead.sectionLength, soCurrent);
    end;
    extra := fs.Position - fs.Size;
    if extra > 0 then
      WriteLn(Format(SWarnExtraBytes, [extra]));

    // Step 1: Only read KIDX
    fs.Seek(SizeOf(filHead), soFromBeginning);
    while fs.Position < fs.Size do
    begin
      fs.Read(secHead, SizeOf(secHead));
      if secHead.sectionKey = 'KIDX' then Break; // do not localize
      fs.Seek(secHead.sectionLength, soCurrent);
    end;
    if secHead.sectionKey <> 'KIDX' then // do not localize
    begin
      raise Exception.CreateFmt(SSectionNotFound, ['KIDX']); // do not localize
    end;
    Result := nil;
    SetLength(Result, secHead.sectionLength);
    fs.ReadBuffer(Result[0], secHead.sectionLength);
  end;

{$IFDEF FPC}
var
  FileStream: TFileStream;
  FileName: string;
begin
  FileName := ExtractFilePath(ParamStr(0)) + 'kanji.dat'; // do not localize
  FileStream := TFileStream.Create(FileName, fmOpenRead);
  try
    Result := ParseKanjiDat(FileStream);
  finally
    FreeAndNil(FileStream);
  end;
{$ELSE}
var
  ResStream: TResourceStream;
begin
  ResStream := TResourceStream.Create(HInstance, 'KANJI_DAT', RT_RCDATA); // do not localize
  try
    Result := ParseKanjiDat(ResStream);
  finally
    FreeAndNil(ResStream);
  end;
{$ENDIF}
end;

function IsKanjiValid(const Data: TBytes; Value: Word): Boolean;
var
  Offset: Integer;
  Entry: Word;
begin
  Offset := Value * 2;
  if Offset < $FF then Offset := Offset shl 8; // TODO: this is weird! adjust the documentation?!
  if Offset + 1 >= Length(Data) then
    Exit(False);
  Entry := PWord(@Data[Offset])^;
  Result := Entry <> $FFFF;
end;

// --- GXT/TXT Converter Methods

procedure GxtToTxt(const InFile, OutFile: string);

  function GTA2toANSI_J(s: WideString): WideString;
  var
    i: Integer;
    w: Word;
    b: TBytes;
    enc: TEncoding;
  begin
    Result := '';
    enc := MakeEncoding(CP_SJIS);

    try
      for i := 1 to Length(s) do
      begin
        w := Word(s[i]);

        { ASCII / normal UTF-16 low chars }
        if w <= $007F then
        begin
          Result := Result + WideChar(w);
        end
        else
        begin
          { treat WideChar as packed SJIS bytes }
          SetLength(b, 2);
          b[0] := Byte(w shr 8);   // high byte
          b[1] := Byte(w and $FF); // low byte

          { if first byte zero -> single byte }
          if b[0] = 0 then
          begin
            b[0] := b[1];
            SetLength(b, 1);
          end;

          {$IFDEF FPC}
          Result := Result + Utf8Decode(BytesToRawString(ConvertWithIconv(b, MakeEncoding(CP_SJIS), MakeEncoding(CP_UTF8))));
          {$ELSE}
          Result := Result + enc.GetString(b);
          {$ENDIF}
        end;
      end;
    finally
      enc.Free;
    end;
  end;

  function GTA2toANSI_EU(s: WideString): WideString;
  var
    i, j: integer;
  begin
    result := s;
    for i := 1 to Length(s) do
    begin
      for j := Low(EU_Charset_Convert) to High(EU_Charset_Convert) do
      begin
        if Ord(result[i]) = Ord(EU_Charset_Convert[j][0]) then
        begin
          result[i] := WideChar(Ord(EU_Charset_Convert[j][1]));
          break;
        end;
      end;
    end;
  end;

  function BytesToWideStringRaw(const Bytes: TBytes): WideString;
  var
    Len: Integer;
  begin
    Len := Length(Bytes) div 2; // each WideChar = 2 bytes
    SetLength(Result, Len);
    if Len > 0 then
      Move(Bytes[0], Result[1], Len * SizeOf(WideChar));
  end;

  type
    TDecodeGXTAnswer = record
      Language: AnsiChar;
      Messages: TGTAMessagesArray;
    end;

  function DecodeGXT(fs: TFileStream): TDecodeGXTAnswer;
  var
    numEntries: integer;
    i, j: integer;
    filHead: TGTA2Header;
    tkAry: array of TKEYEntry;
    tkLen: integer;
    secHead: TGTA2SectionHeader;
    ws: WideString;
    extra: integer;
    p: pByte;
    op: PWideChar;
    msgBytes: TBytes;
    len: integer;
    s: String;
    KanjiIdx: TBytes;
  begin
    fs.Position := 0;

    fs.Read(filHead, SizeOf(filHead));

    result.Language := filHead.lang;

    if result.Language = 'R' then
      raise Exception.Create('Russian language not implemented yet'); // TODO: Implement Russian

    if result.Language = 'J' then // do not localize
      KanjiIdx := LoadKanjiDat;

    // Optional checks
    if filHead.magic <> GXT_MAGIC then
      raise Exception.CreateFmt(SMagicHeaderMissing, [GXT_MAGIC]);
    if filHead.version <> GXT_VER then
      raise Exception.CreateFmt(SWrongFileVersion, [GXT_MAGIC, GXT_VER]);
    fs.Seek(SizeOf(filHead), soFromBeginning);
    while fs.Position < fs.Size do
    begin
      fs.Read(secHead, SizeOf(secHead));
      if (secHead.sectionKey <> 'TKEY') and (secHead.sectionKey <> 'TDAT') then // do not localize
        WriteLn(Format(SUnknownSectionType_S, [secHead.sectionKey]));
      fs.Seek(secHead.sectionLength, soCurrent);
    end;
    extra := fs.Position - fs.Size;
    if extra > 0 then
      WriteLn(Format(SWarnExtraBytes, [extra]));

    // Step 1: Collect all keys
    fs.Seek(SizeOf(filHead), soFromBeginning);
    while fs.Position < fs.Size do
    begin
      fs.Read(secHead, SizeOf(secHead));
      if secHead.sectionKey = 'TKEY' then Break; // do not localize
      fs.Seek(secHead.sectionLength, soCurrent);
    end;
    if secHead.sectionKey <> 'TKEY' then // do not localize
    begin
      raise Exception.CreateFmt(SSectionNotFound, ['TKEY']); // do not localize
    end;
    tkLen := secHead.sectionLength;
    numEntries := tkLen div SizeOf(TKEYEntry);
    SetLength(tkAry, numEntries);
    fs.Read(tkAry[0], tkLen);

    // Step 2: Collect all texts
    fs.Seek(SizeOf(filHead), soFromBeginning);
    while fs.Position < fs.Size do
    begin
      fs.Read(secHead, SizeOf(secHead));
      if secHead.sectionKey = 'TDAT' then Break; // do not localize
      fs.Seek(secHead.sectionLength, soCurrent);
    end;
    if secHead.sectionKey <> 'TDAT' then // do not localize
    begin
      raise Exception.CreateFmt(SSectionNotFound, ['TDAT']); // do not localize
    end;
    SetLength(ws, secHead.sectionLength div SizeOf(WideChar));
    fs.Read(ws[1], secHead.sectionLength);

    // Step 3: Generating output "messages" Variable
    op := PWideChar(ws);
    SetLength(result.Messages, numEntries);
    for i := 0 to numEntries-1 do
    begin
      p := PByte(op) + tkAry[i].relDataOffset;

      len := 0;

      { scan UTF-16 zero terminator #0#0 }
      while not ((p[len] = 0) and (p[len + 1] = 0)) do
        Inc(len, SizeOf(WideChar));
      SetLength(msgBytes, len);
      if Len > 0 then
        Move(p^, msgBytes[0], len);

      // Decode Speaker
      result.Messages[i].guy := #0;
      if Len > 1 then
      begin
        if msgBytes[1] = Ord('!') then
        begin
          result.Messages[i].guy := AnsiChar(msgBytes[0]);
          Move(msgBytes[2], msgBytes[0], Length(msgBytes) - 2);
          SetLength(msgBytes, Length(msgBytes) - 2);
        end;
      end;

      {$IFDEF FPC}
      result.Messages[i].msg := BytesToWideStringRaw(msgBytes);
      {$ELSE}
      result.Messages[i].msg := TEncoding.Unicode.GetString(msgBytes);
      {$ENDIF}

      if filHead.lang = 'J' then
      begin

        // BUG IN J.GXT: SJIS 0x8140 : IDEOGRAPHIC SP (U+3000), not in Kanji.dat
        for j := 1 to Length(result.Messages[i].msg) do
          if Word(result.Messages[i].msg[j]) = $8140 then
            if not IsKanjiValid(KanjiIdx, Word(result.Messages[i].msg[j])) then
              result.Messages[i].msg[j] := ' '; // silently replace it with a regular whitespace

        // Convert JSIS-16 to UTF-16
        result.Messages[i].msg := GTA2toANSI_J(result.Messages[i].msg);
      end
      else
        result.Messages[i].msg := GTA2toANSI_EU(result.Messages[i].msg);

      s := string(PAnsiChar(@tkAry[i].key[0])); // stops at #0

      // BUG IN BOB_J.GXT: They accidentally translated "/" (U+002F) to "／" (U+FF0F) in the key!
      //                   Silently fix it by replacing it with "/" 
      s := StringReplace(s, #$81#$5E, '/', []);

      result.Messages[i].key := AnsiString(s);
    end;
  end;

var
  ans: TDecodeGXTAnswer;
  messages: TGTAMessagesArray;
  fs, fsOut: TFileStream;
  i: integer;
  speaker: string;
  rbs: RawByteString;
const
  bom: array[0..2] of Byte = ($EF, $BB, $BF);
begin
  fs := TFileStream.Create(InFile, fmOpenRead);
  fsOut := TFileStream.Create(OutFile, fmCreate or fmOpenWrite);
  try
    fsOut.WriteBuffer(bom, SizeOf(bom));

    ans := DecodeGXT(fs);
    messages := ans.Messages;
    for i := low(messages) to high(messages) do
    begin
      if messages[i].guy <> #0 then
      begin
        speaker := messages[i].guy + '!';
      end
      else
        speaker := '';

      rbs := UTF8Encode('[' + WideString(messages[i].key) + '] ' + WideString(speaker) + messages[i].msg + #13#10);
      fsOut.WriteBuffer(Pointer(rbs)^, Length(rbs));
    end;

  finally
    FreeAndNil(fs);
    FreeAndNil(fsOut);
  end;

  WriteLn(Format(S_OK_S_S_LANG_S, [InFile, OutFile, ans.Language]));
end;

procedure TxtToGxt(const InFile, OutFile: string; Language: Char);
var
  KanjiIdx: TBytes;

  function Unused_WideStringToBytes(const S: WideString): TBytes;
  begin
    Result := nil;
    if Length(S) > 0 then
    begin
      SetLength(Result, Length(S) * SizeOf(WideChar));
      Move(PWideChar(S)^, Result[0], Length(Result));
    end;
  end;

  function ANSItoGTA2_J(s: WideString): WideString;
  var
    i: Integer;
    ch: WideString;
    b: TBytes;
    w: Word;
    enc: TEncoding;
  begin
    Result := '';
    enc := MakeEncoding(CP_SJIS); // CP932 / Shift-JIS

    try
      for i := 1 to Length(s) do
      begin
        ch := s[i];

        if Ord(ch[1]) <= $7F then
        begin
          { ASCII stays UTF-16 ASCII }
          Result := Result + WideChar(Ord(ch[1]));
        end
        else
        begin
          { Rest becomes Shift-JIS, but always 16 bit }
          {$IFDEF FPC}
          b := ConvertWithIconv(RawByteStringToBytes(Utf8Encode(s[i])), MakeEncoding(CP_UTF8), MakeEncoding(CP_SJIS));
          {$ELSE}
          b := enc.GetBytes(ch);
          {$ENDIF}

          if Length(b) = 1 then
            w := b[0]
          else
            w := (Word(b[0]) shl 8) or Word(b[1]);

          Result := Result + WideChar(w);
        end;
      end;
    finally
      enc.Free;
    end;
  end;

  function ANSItoGTA2_EU(s: WideString): WideString;
  var
    i, j: integer;
  begin
    result := s;
    for i := 1 to Length(s) do
    begin
      for j := Low(EU_Charset_Convert) to High(EU_Charset_Convert) do
      begin
        if Ord(result[i]) = Ord(EU_Charset_Convert[j][1]) then
        begin
          result[i] := WideChar(Ord(EU_Charset_Convert[j][0]));
          break;
        end;
      end;
    end;
  end;

  function ZeroPad(s: string; len: integer): string;
  begin
    result := s;
    while Length(result) < len do result := result + #0;
  end;

  procedure EncodeGXT(messages: TGTAMessagesArray; fsOut: TFileStream; lang: Char);
  var
    i: integer;
    msg: WideString;
    guywc: WideChar;
    curoffset: Cardinal;
    curkey: AnsiString;
    msKey, msDat: TMemoryStream;
    gxtHead: TGTA2Header;
    secHead: TGTA2SectionHeader;
    j: integer;
    sjis: word;
  begin
    if lang = 'R' then
      raise Exception.Create('Russian language not implemented yet'); // TODO: Implement Russian

    msKey := TMemoryStream.Create;
    msDat := TMemoryStream.Create;
    try
      msKey.Size := 0;
      msDat.Size := 0;
      for i := Low(messages) to High(messages) do
      begin
        if Length(messages[i].key) > 7 then
        begin
          WriteLn(Format(SLineTooLongIgnored, [messages[i].key]));
          Continue;
        end;

        curoffset := msDat.Position;
        msKey.Write(curoffset, SizeOf(curoffset));
        curkey := AnsiString(ZeroPad(string(messages[i].key), MAX_KEY_SIZE));
        msKey.Write(curkey[1], Length(curkey)*SizeOf(AnsiChar));

        if lang = 'J' then
        begin
          msg := ANSItoGTA2_J(messages[i].msg);

          for j := Low(msg) to High(msg) do
          begin
            Sjis := Word(msg[j]);
            if not (Sjis in [{ $0A, $0D, }$20]) and not IsKanjiValid(KanjiIdx, Sjis) then
            begin
              // BUG IN J.GXT: SJIS 0x8140 : IDEOGRAPHIC SPACE (U+3000), not in Kanji.dat
              if Sjis = $8140 then
                msg[j] := ' ' // silently fix it by replacing it with a normal space
              else
                WriteLn(Format(S_IllegalKanji, ['0x' + IntToHex(Sjis, 4)]));
            end;
          end;

        end
        else
          msg := ANSItoGTA2_EU(messages[i].msg);

        msg := msg + #0;

        if messages[i].guy <> #0 then
        begin
          guywc := WideChar(Ord(messages[i].guy) + Ord('!') shl 8);
          msg := guywc + msg;
        end;

        msDat.Write(msg[1], Length(msg) * SizeOf(WideChar));
      end;

      gxtHead.magic   := GXT_MAGIC;
      gxtHead.lang    := AnsiChar(lang);
      gxtHead.version := GXT_VER;
      fsOut.Write(gxtHead, SizeOf(gxtHead));

      secHead.sectionKey := 'TKEY'; // do not localize
      secHead.sectionLength := msKey.Size;
      fsOut.Write(secHead, SizeOf(secHead));
      msKey.Position := 0;
      fsOut.CopyFrom(msKey, msKey.Size);

      secHead.sectionKey := 'TDAT'; // do not localize
      secHead.sectionLength := msDat.Size;
      fsOut.Write(secHead, SizeOf(secHead));
      msDat.Position := 0;
      fsOut.CopyFrom(msDat, msDat.Size);
    finally
      FreeAndNil(msKey);
      FreeAndNil(msDat);
    end;
  end;

  function LineToMessage(line: WideString; var m: TGTAMessage): boolean;
  var
    p: integer;
    key: AnsiString;
    msg: WideString;
    guy: AnsiChar;
    wkey: WideString;
    i: integer;
  begin
    result := false;

    if Trim(line) = '' then Exit;

    if (Copy(line, 1, 1) <> '[') then
    begin
      WriteLn(Format(SInvalidLineIgnored, [line]));
      Exit;
    end;

    p := Pos(']', line);

    // BUG IN BOB_J.GXT: They accidentally translated "/" (U+002F) to "／" (U+FF0F) in the key!
    //                   Silently fix it by replacing it with "/" 
    wkey := Copy(line, 2, p-2);
    for i := 1 to Length(wkey) do
      if wkey[i] = #$FF0F then
        wkey[i] := '!';

    key := AnsiString(wkey);

    if (Copy(line, p+1, 1) <> ' ') then
    begin
      WriteLn(Format(SInvalidLine, [line]));
      Exit;
    end;

    msg := Copy(line, p+2, Length(line)-p-1);

    if Copy(msg, 2, 1) = '!' then
    begin
      guy := AnsiChar(msg[1]);
      msg := Copy(msg, 3, Length(msg)-2);
    end
    else
      guy := #0;

    m.key := key;
    m.guy := guy;
    m.msg := msg;

    result := true;
  end;

{$IFDEF FPC}
  function DecodeFPC(const B: TBytes; Info: TFileEncInfo): WideString;
  begin
    if Info.IsUtf8 then
      Result := UTF8Decode(BytesToRawString(ConvertWithIconv(B, Info.Encoding, MakeEncoding(CP_UTF8))))
    else if Info.IsJapanese then
      Result := UTF8Decode(BytesToRawString(ConvertWithIconv(B, MakeEncoding(CP_SJIS), MakeEncoding(CP_UTF8))))
    else
      Result := UTF8Decode(BytesToRawString(ConvertWithIconv(B, MakeEncoding(CP_EURO), MakeEncoding(CP_UTF8))));
  end;
{$ELSE}
  function DecodeDelphi(const B: TBytes; Info: TFileEncInfo): WideString;
  var
    P: Integer;
    Len: Integer;
  begin
    if Length(B) = 0 then
      Exit('');

    P := 0;
    Len := Length(B);

    // Skip UTF8 BOM
    if info.IsUtf8 and (Len >= 3) and
       (B[0] = $EF) and (B[1] = $BB) and (B[2] = $BF) then
    begin
      P := 3;
      Dec(Len, 3);
    end;

    if Assigned(info.Encoding) then
      Result := info.Encoding.GetString(B, P, Len)
    else if info.IsUtf8 then
      Result := TEncoding.UTF8.GetString(B, P, Len)
    else if info.IsJapanese then
      Result := MakeEncoding(CP_SJIS).GetString(B, P, Len)
    else
      Result := MakeEncoding(CP_EURO).GetString(B, P, Len);
  end;
{$ENDIF}

function SplitLines(const S: WideString): TArray<WideString>;
var
  i, Start, Count: Integer;
begin
  Result := nil;
  SetLength(Result, 0);
  Count := 0;
  Start := 1;
  i := 1;

  while i <= Length(S) do
  begin
    if (S[i] = #10) or (S[i] = #13) then
    begin
      if i > Start then
      begin
        SetLength(Result, Count + 1);
        Result[Count] := Copy(S, Start, i - Start);
        Inc(Count);
      end;

      // CRLF sauber überspringen ohne i+1 Zugriff
      if (S[i] = #13) then
      begin
        if (i < Length(S)) and (S[i + 1] = #10) then
          Inc(i);
      end;

      Start := i + 1;
    end;

    Inc(i);
  end;

  if Start <= Length(S) then
  begin
    SetLength(Result, Count + 1);
    Result[Count] := Copy(S, Start, Length(S) - Start + 1);
  end;
end;

var
  InBytes: TBytes;
  Info: TFileEncInfo;
  IsJapanese: boolean;
  S: WideString;
  i: integer;
  m: TGTAMessage;
  messages: TGTAMessagesArray;
  fsOut: TFileStream;
  Lines: TArray<WideString>;
begin
  Info := DetectFileEncoding(InFile);

  IsJapanese := Info.IsJapanese;
  if IsJapanese then
    KanjiIdx := LoadKanjiDat;
  InBytes := ReadTextFileWithEncoding(InFile, Info.FileEncoding, Info.Encoding);

{$IFDEF FPC}
  S := DecodeFPC(InBytes, Info);
{$ELSE}
  S := DecodeDelphi(InBytes, Info);
{$ENDIF}

  Lines := SplitLines(S);

  // Convert TXT lines to GTA2 messages
  messages := nil;
  SetLength(messages, 0);
  for i := Low(Lines) to High(Lines) do
  begin
    if not LineToMessage(Lines[i], m) then Continue;
    SetLength(messages, Length(messages) + 1);
    messages[High(messages)] := m;
  end;

  // TODO: We might want to order the messages so that they are sorted by TKEY (this seems to be important to the game)

  // Now write messages to GXT file
  fsOut := TFileStream.Create(Outfile, fmCreate or fmOpenWrite);
  try
    EncodeGXT(messages, fsOut, Language);
  finally
    FreeAndNil(fsOut);
  end;

  WriteLn(Format(S_OK_S_S_LANG_S, [InFile, OutFile, Language]));
end;

// --- Main Methods (CLI)

procedure ShowUsage;
begin
  Writeln(S_INTRO_1);
  Writeln(S_INTRO_2);
  Writeln(S_INTRO_3);
  Writeln(S_INTRO_4);
  Writeln('');
  Writeln(S_USAGE);
  {$IFDEF MSWINDOWS}
  Writeln('  '+UpperCase(ExtractFileName(ParamStr(0)))+' input.gxt');
  Writeln('  '+UpperCase(ExtractFileName(ParamStr(0)))+' input.txt');
  {$ELSE}
  Writeln('  ./'+ExtractFileName(ParamStr(0))+' input.gxt [outfile.txt]');
  Writeln('  ./'+ExtractFileName(ParamStr(0))+' input.txt [outfile.gxt] [E|G|F|I|S|R|J]');
  {$ENDIF}
  Writeln;
end;

function CompareFiles(const File1, File2: string): Boolean;
const
  BufferSize = 64 * 1024; // 64 KB
var
  Stream1, Stream2: TFileStream;
  Buffer1, Buffer2: TBytes;
  Read1, Read2: Integer;
begin
  Result := False;

  if not FileExists(File1) then
  begin
    Writeln('Error: ' + Format(SFileNotFound, [File1]));
    Exit;
  end;

  if not FileExists(File2) then
  begin
    Writeln('Error: ' + Format(SFileNotFound, [File2]));
    Exit;
  end;

  Stream1 := TFileStream.Create(File1, fmOpenRead or fmShareDenyWrite);
  Stream2 := TFileStream.Create(File2, fmOpenRead or fmShareDenyWrite);
  try
    // Check file size first
    if Stream1.Size <> Stream2.Size then
    begin
      Writeln(Format('TEST FAILURE: File size differs: %s %d <> %s %d)',
        [File1, Stream1.Size, File2, Stream2.Size]));
      Exit;
    end;

    SetLength(Buffer1, BufferSize);
    SetLength(Buffer2, BufferSize);

    repeat
      Read1 := Stream1.Read(Buffer1[0], BufferSize);
      Read2 := Stream2.Read(Buffer2[0], BufferSize);

      if Read1 <> Read2 then
      begin
        Writeln('TEST FAILURE: File contents differ '+File1+' <=> '+File2);
        Exit;
      end;

      if not CompareMem(@Buffer1[0], @Buffer2[0], Read1) then
      begin
        Writeln('TEST FAILURE: File contents differ '+File1+' <=> '+File2);
        Exit;
      end;
    until Read1 = 0;

    WriteLn('OK: (Binary comparison '+File1+' <=> '+File2+')');
    Result := True;
  finally
    FreeAndNil(Stream1);
    FreeAndNil(Stream2);
  end;
end;

procedure Testcases;
const
  {$IFDEF MSWINDOWS}
  TestDir = 'gxt_original\';
  {$ELSE}
  TestDir = 'gxt_original/';
  {$ENDIF}
begin
  GxtToTxt(TestDir + 'e.gxt', TestDir + 'e.txt');
  TxtToGxt(TestDir + 'e.txt', TestDir + 'e2.gxt', 'E');
  GxtToTxt(TestDir + 'e2.gxt', TestDir + 'e2.txt');
  CompareFiles(TestDir + 'e.txt', TestDir + 'e2.txt');
  // TODO: Currently our re-generated GXT files do NOT fit the original
  //       GXT files. The reason is that GXT=>TXT does order the output
  //       according to the pre-ordered TKEYs, not according to the TDAT.
  //       Probably better would be if GXT=>TXT orders by TDAT.
  //       But if we do that, then TXT=>GXT needs to order to TKEY
  //       instead of just taking the order from TXT. (The ordering to TKEY
  //       is probably important to the game).
  //CompareFiles(TestDir + 'e.gxt', TestDir + 'e2.gxt');

  GxtToTxt(TestDir     + 'f.gxt',  TestDir + 'f.txt');
  TxtToGxt(TestDir     + 'f.txt',  TestDir + 'f2.gxt', 'F');
  GxtToTxt(TestDir     + 'f2.gxt', TestDir + 'f2.txt');
  CompareFiles(TestDir + 'f.txt',  TestDir + 'f2.txt');
  //CompareFiles(TestDir + 'f.gxt', TestDir + 'f2.gxt');

  GxtToTxt(TestDir     + 'g.gxt',  TestDir + 'g.txt');
  TxtToGxt(TestDir     + 'g.txt',  TestDir + 'g2.gxt', 'G');
  GxtToTxt(TestDir     + 'g2.gxt', TestDir + 'g2.txt');
  CompareFiles(TestDir + 'g.txt',  TestDir + 'g2.txt');
  //CompareFiles(TestDir + 'g.gxt', TestDir + 'g2.gxt');

  GxtToTxt(TestDir     + 'i.gxt',  TestDir + 'i.txt');
  TxtToGxt(TestDir     + 'i.txt',  TestDir + 'i2.gxt', 'I');
  GxtToTxt(TestDir     + 'i2.gxt', TestDir + 'i2.txt');
  CompareFiles(TestDir + 'i.txt',  TestDir + 'i2.txt');
  //CompareFiles(TestDir + 'i.gxt', TestDir + 'i2.gxt');

  GxtToTxt(TestDir + 'j.gxt', TestDir + 'j.txt');
  TxtToGxt(TestDir + 'j.txt', TestDir + 'j2.gxt', 'J');
  GxtToTxt(TestDir + 'j2.gxt', TestDir + 'j2.txt');
  CompareFiles(TestDir + 'j.txt', TestDir + 'j2.txt');
  //CompareFiles(TestDir + 'j.gxt', TestDir + 'j2.gxt');

  // TODO: Implement/Research Russian
  (*
  GxtToTxt(TestDir     + 'r.gxt',  TestDir + 'r.txt');
  TxtToGxt(TestDir     + 'r.txt',  TestDir + 'r2.gxt', 'R');
  GxtToTxt(TestDir     + 'r2.gxt', TestDir + 'r2.txt');
  CompareFiles(TestDir + 'r.txt',  TestDir + 'r2.txt');
  //CompareFiles(TestDir + 'r.gxt', TestDir + 'r2.gxt');
  *)

  GxtToTxt(TestDir     + 's.gxt',  TestDir + 's.txt');
  TxtToGxt(TestDir     + 's.txt',  TestDir + 's2.gxt', 'S');
  GxtToTxt(TestDir     + 's2.gxt', TestDir + 's2.txt');
  CompareFiles(TestDir + 's.txt',  TestDir + 's2.txt');
  //CompareFiles(TestDir + 's.gxt', TestDir + 's2.gxt');

  GxtToTxt(TestDir + 'bob_e.gxt', TestDir + 'bob_e.txt');
  TxtToGxt(TestDir + 'bob_e.txt', TestDir + 'bob_e2.gxt', 'E');
  GxtToTxt(TestDir + 'bob_e2.gxt', TestDir + 'bob_e2.txt');
  CompareFiles(TestDir + 'bob_e.txt', TestDir + 'bob_e2.txt');
  //CompareFiles(TestDir + 'bob_e.gxt', TestDir + 'bob_e2.gxt');

  GxtToTxt(TestDir     + 'bob_f.gxt',  TestDir + 'bob_f.txt');
  TxtToGxt(TestDir     + 'bob_f.txt',  TestDir + 'bob_f2.gxt', 'F');
  GxtToTxt(TestDir     + 'bob_f2.gxt', TestDir + 'bob_f2.txt');
  CompareFiles(TestDir + 'bob_f.txt',  TestDir + 'bob_f2.txt');
  //CompareFiles(TestDir + 'bob_f.gxt', TestDir + 'bob_f2.gxt');

  GxtToTxt(TestDir     + 'bob_g.gxt',  TestDir + 'bob_g.txt');
  TxtToGxt(TestDir     + 'bob_g.txt',  TestDir + 'bob_g2.gxt', 'G');
  GxtToTxt(TestDir     + 'bob_g2.gxt', TestDir + 'bob_g2.txt');
  CompareFiles(TestDir + 'bob_g.txt',  TestDir + 'bob_g2.txt');
  //CompareFiles(TestDir + 'bob_g.gxt', TestDir + 'bob_g2.gxt');

  GxtToTxt(TestDir     + 'bob_i.gxt',  TestDir + 'bob_i.txt');
  TxtToGxt(TestDir     + 'bob_i.txt',  TestDir + 'bob_i2.gxt', 'I');
  GxtToTxt(TestDir     + 'bob_i2.gxt', TestDir + 'bob_i2.txt');
  CompareFiles(TestDir + 'bob_i.txt',  TestDir + 'bob_i2.txt');
  //CompareFiles(TestDir + 'bob_i.gxt', TestDir + 'bob_i2.gxt');

  GxtToTxt(TestDir + 'bob_j.gxt', TestDir + 'bob_j.txt');
  TxtToGxt(TestDir + 'bob_j.txt', TestDir + 'bob_j2.gxt', 'J');
  GxtToTxt(TestDir + 'bob_j2.gxt', TestDir + 'bob_j2.txt');
  CompareFiles(TestDir + 'bob_j.txt', TestDir + 'bob_j2.txt');
  //CompareFiles(TestDir + 'bob_j.gxt', TestDir + 'bob_j2.gxt');

  // TODO: Implement/Research Russian
  (*
  GxtToTxt(TestDir     + 'bob_r.gxt',  TestDir + 'bob_r.txt');
  TxtToGxt(TestDir     + 'bob_r.txt',  TestDir + 'bob_r2.gxt', 'R');
  GxtToTxt(TestDir     + 'bob_r2.gxt', TestDir + 'bob_r2.txt');
  CompareFiles(TestDir + 'bob_r.txt',  TestDir + 'bob_r2.txt');
  //CompareFiles(TestDir + 'bob_r.gxt', TestDir + 'bob_r2.gxt');
  *)

  GxtToTxt(TestDir     + 'bob_s.gxt',  TestDir + 'bob_s.txt');
  TxtToGxt(TestDir     + 'bob_s.txt',  TestDir + 'bob_s2.gxt', 'S');
  GxtToTxt(TestDir     + 'bob_s2.gxt', TestDir + 'bob_s2.txt');
  CompareFiles(TestDir + 'bob_s.txt',  TestDir + 'bob_s2.txt');
  //CompareFiles(TestDir + 'bob_s.gxt', TestDir + 'bob_s2.gxt');

  {$IFDEF MSWINDOWS}
  WriteLn(S_PRESS_ANY_KEY);
  ReadLn;
  exit;
  {$ENDIF}
end;

function GuessOrAskForLanguage(const InFile: string): Char;
var
  chTmp: Char;
  sTmp: string;
begin
  Result := ' ';
  for chTmp in ['E', 'G', 'F', 'I', 'S', 'R', 'J'] do
    if SameText(ExtractFileName(InFile), chTmp + '.TXT') or SameText(ExtractFileName(InFile), 'BOB_' + chTmp + '.TXT') then Result := chTmp;
  while not CharInSet(Result, ['E', 'G', 'F', 'I', 'S', 'R', 'J']) do
  begin
    WriteLn(Format(S_ENTER_LANGUAGE, [InFile]));
    ReadLn(sTmp);
    if sTmp = '' then sTmp := ' ';
    Result := UpCase(sTmp[1]);
  end;
end;

{$IFDEF MSWINDOWS}
procedure ProcessFile(const InFile: string; var RequirePause: boolean);
var
  Lang: Char;
begin
  try
    Lang := GuessOrAskForLanguage(InFile);
         if ExtractFileExt(InFile)         = '.gxt'  then GxtToTxt(InFile, ChangeFileExt(InFile, '.txt'))
    else if ExtractFileExt(InFile)         = '.GXT'  then GxtToTxt(InFile, ChangeFileExt(InFile, '.TXT'))
    else if SameText(ExtractFileExt(InFile), '.gxt') then GxtToTxt(InFile, ChangeFileExt(InFile, '.txt'))
    else if ExtractFileExt(InFile)         = '.txt'  then TxtToGxt(InFile, ChangeFileExt(InFile, '.gxt'), Lang)
    else if ExtractFileExt(InFile)         = '.TXT'  then TxtToGxt(InFile, ChangeFileExt(InFile, '.GXT'), Lang)
    else if SameText(ExtractFileExt(InFile), '.txt') then TxtToGxt(InFile, ChangeFileExt(InFile, '.gxt'), Lang)
    else
    begin
      if FileExists(InFile) then
        raise Exception.Create(S_INVALID_FILE)
      else
        raise Exception.Create(S_INVALID_PARAM);
    end;
  except
    on E: Exception do
    begin
      WriteLn(Format(S_ERR_S_S, [InFile, E.Message]));
      RequirePause := true;
    end;
  end;
end;

procedure ExpandAndProcess(const AArg: string; var RequirePause: boolean);
var
  DirPart, Pattern: string;
  Files: TArray<string>;
  FileName: string;
begin
  if (Pos('*', AArg) > 0) or (Pos('?', AArg) > 0) then
  begin
    DirPart := ExtractFilePath(AArg);
    Pattern := ExtractFileName(AArg);

    if DirPart = '' then
      DirPart := GetCurrentDir;

    Files := TDirectory.GetFiles(DirPart, Pattern, TSearchOption.soTopDirectoryOnly);

    for FileName in Files do
      ProcessFile(FileName, RequirePause);
  end
  else
  begin
    ProcessFile(ExpandFileName(AArg), RequirePause);
  end;
end;
{$ENDIF}

procedure Main;
{$IFDEF MSWINDOWS}
var
  i: integer;
  RequirePause: boolean;
begin
  if ParamCount < 1 then
  begin
    RequirePause := true;
    ShowUsage;
  end
  else
  begin
    RequirePause := false;
    for i := 1 to ParamCount do
    begin
      if ParamStr(i) = 'TEST' then
      begin
        try
          Testcases
        except
          on E: Exception do
          begin
            WriteLn(Format('Testcases Exception: %s', [e.Message]));
            RequirePause := true;
          end;
        end;
      end
      else
      ExpandAndProcess(ParamStr(i), RequirePause);
    end;
  end;

  if RequirePause then
  begin
    WriteLn(S_PRESS_ANY_KEY);
    ReadLn;
  end;
{$ELSE}
var
  InFile, OutFile, Ext: string;
  Lang: Char;
begin
  if ParamCount < 1 then
  begin
    ShowUsage;
    Exit;
  end;

  InFile := ParamStr(1);
  if InFile = 'TEST' then
  begin
    Testcases;
    Exit;
  end;

  if ParamCount >= 2 then
    OutFile := ParamStr(2)
  else
  begin
    Ext := LowerCase(ExtractFileExt(InFile));
    if Ext = '.gxt' then
      OutFile := ChangeFileExt(InFile, '.txt')
    else if Ext = '.txt' then
      OutFile := ChangeFileExt(InFile, '.gxt')
    else
      raise Exception.Create(S_INVALID_FILE);
  end;

  Ext := LowerCase(ExtractFileExt(InFile));
  if Ext = '.gxt' then
    GxtToTxt(InFile, OutFile)
  else if Ext = '.txt' then
  begin
    if ParamCount >= 3 then
      Lang := ParamStr(3)[1]
    else
      Lang := GuessOrAskForLanguage(InFile);
    TxtToGxt(InFile, OutFile, Lang);
  end
  else
    raise Exception.Create(S_INVALID_FILE);
{$ENDIF}
end;

begin
  try
    Main;
  except
    on E: Exception do
    begin
      Writeln(Format(S_ERR_S_S, [E.ClassName, E.Message]));
      {$IFDEF FPC}
      Halt(1);
      {$ELSE}
      ExitCode := 1;
      {$ENDIF}
    end;
  end;
end.
