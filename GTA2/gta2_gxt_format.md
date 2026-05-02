GTA 2 GXT Format
================

Description
-----------

The GXT format contains language specific texts of the game.

GXT↔TXT Converter
-----------------

This converter tool allows you to convert GXT files to TXT and vice versa.  
It fully supports all languages, including Japanese and Russian, and corrects many issues that other converters handle incorrectly.  
It has been thoroughly tested with all official GXT files, and converting from TXT back to GXT reproduces the original file exactly, bit for bit.  
It also detects illegal characters such as non-implemented European accent characters or Japanese Kanji characters which are not implemented in the game.  
For this reason, this converter is as accurate and reliable as possible.

[**Download for Windows**](https://misc.daniel-marschall.de/spiele/gta2/language_fix/tools/gxt_converter_v2/GxtToolUnicode.exe)
Usage: Just drag'n'drop an GXT or TXT file into the EXE. It will then create an converted GXT/TXT file in the same directory.
Alternatively, use it via command line (cmd.exe).

[**Download for Linux**](https://misc.daniel-marschall.de/spiele/gta2/language_fix/tools/gxt_converter_v2/GxtToolUnicode)  
Usage: Call it in the shell. The arguments are a bit different than the Windows version. To converter Japanese, make sure that KANJI.IDX is present.

[**Source code**](https://github.com/danielmarschall/gta_lang_converter/GTA2) for Delphi (Windows) and FreePascal (Linux)

* * *

Technical notes about the GXT Format
====================================

Files
- C:\GTA2\data\*.gxt (game)
- C:\GTA2\data\bob_*.gxt (game manager)

These files contain language specific texts used in the game.

File structure
--------------

```
<header>
<section>
<section>
...
```

Header
------

```
char[3]	"GBL"
char[1]	"E","G","F","I","S","J","R" (Language)
int16	64 00 (version = 100)
```

Section
-------

```
char[4]	<section type name>, "TKEY" or "TDAT"
int32	length of <section content>
```

Section type: TKEY (contains key names)
---------------------------------------

```
int32	<rel. offset>
char[8]	<zero terminated key name>
int32	<rel. offset>
char[8]	<zero terminated key name>
    	...
```

Since the key is zero terminated, the max key length is 7 characters.
`<rel. offset>` is the offset of the string, relative
to the `<section content>` of the "TDAT" section.

Section type: TDAT (contains texts)
-----------------------------------

```
<zero terminated widestring*>
<zero terminated widestring*>
...
```

* Icon references (first Unicode character, case sensitive):
	`6B 21`	"k!"	Krishna
	`6C 21`	"l!"	Loonies
	`6D 21`	"m!"	Russian
	`6E 21`	"n!"	Neutral guy
	`70 21`	"p!"	Police
	`72 21`	"r!"	Rednecks
	`73 21`	"s!"	Scientists
	`79 21`	"y!"	Yakuza
	`7A 21`	"z!"	Zaibatsu
	`xx 21`	where `[xx]` is not one of the above, will result in a program crash
	any other Unicode character at position 0 is handles as normal text, without icon

* The captions usually don't have foreign characters implemented in the *.sty files.

* In mission texts, the default color is yellow.
  Text that is included in `#...#` is blue.
  Text in `##...##` is yellow again, and so on.

* In the credits (key "credits"), there are following format rules
	`*`  = new line
	`#W` = switch to white text
	`#C` = switch to yellow/orange text
	`#B` = switch to blue text
	`#G` = switch to green text

* In the GAME language (e.gxt, g.gxt, etc.), a special character set is used for special characters:

	For European GTA2 (Languages: E, F, G, I, S):

```
		0020	  ! " # $ % & ' ( ) * + , - . /
		0030	0 1 2 3 4 5 6 7 8 9 : ; < = > ?
		0040	@ A B C D E F G H I J K L M N O
		0050	P Q R S T U V W X Y Z [ \ ] ^ _
		0060	´ a b c d e f g h i j k l m n o
		0070	p q r s t u v w x y z { | } ~  
		0080	À Á Â Ä Æ Ç È É Ê Ë Ì Í Î Ï Ò Ó
		0090	Ô Ö Ù Ú Û Ü ß à á â ä æ ç è é ê
		00A0	ë ì í î ï ò ó ô ö ù ú û ü Ñ ñ ¿
		00B0	¡
```

		The rendering is done in the *.sty files.

	For Russian GTA2 (Language: R)

```
		0020	  ! " # $ % & ' ( ) * + , - . /
		0030	0 1 2 3 4 5 6 7 8 9 : ; < = > ?
		0040	@ A B C D E F G H I J K L M N O
		0050	P Q R S T U V W X Y Z [ \ ] ^ _
		0060	´ a b c d e f g h i j k l m n o
		0070	p q r s t u v w x y z { | } ~ 
		0080	À Á Â Ä Æ Ç È É Ê Ë Ì Í Î Ï Ò Ó
		0090	Ô Ö Ù Ú Û Ü ß à á â ä æ ç è é ê
		00A0	ë ì í î ï ò ó ô ö ù ú û ü Ñ ñ ¿
		00B0	¡ Ё Й Ц У К Е Н Г Ш Щ З Х Ъ Ф Ы
		00C0	В А П Р О Л Д Ж Э Я Ч С М И Т Ь
		00D0	Б Ю ё й ц у к е н г ш щ з х ъ ф
		00E0	ы в а п р о л д ж э я ч с м и т
		00F0	ь б ю
```
		What order do the russian characters have? It's the order of the JCUKEN keyboard keys!
```
		B1..D1	Ё ЙЦУКЕНГШЩЗХЪ ФЫВАПРОЛДЖЭ ЯЧСМИТЬБЮ
		D2..F2	ё йцукенгшщзхъ фывапролджэ ячсмитьбю
```
    
		The rendering is done in the *.sty files.

	For Japanese GTA2 (Language: J)
	
		Each 16 bit character in the GXT file is either:
		- An UTF-16 encoded ASCII character
		- A Shift-JIS encoded character
		- Single-byte characters are stored as xx00, while double-byte Shift-JIS characters are stored in a 16-bit code unit with swapped byte order.

		The rendering is done in the *.sty files, in addition with 16x16 glyphs implemented in Kanji.dat

* The GAME MANAGER Language (bob_*.gxt) as well as the "netui" keys in the main language file contain characters in the ANSI encoding:

	The "intended" codepages are:
	- For European (E, F, G, I, S) = Codepage 1252
	- For Russian  (R)             = Codepage 1251
	- For Japanese (J)             = Shift-JIS, in the same way as the game file, so there is no difference between bob_j.gxt and j.gxt

	If the player's computer has the wrong codepage, the game manager will show garbage.

* The inofficial [polish version](https://archive.org/details/grand-theft-auto-2-zlota-edycja-poland) replaces the English language (e.gxt, bob_e.gxt). To implement the additional polish characters, unused characters in the default charset are changed in the *.sty files as follows:

```
		" <=> ą
		% <=> ś
		( <=> ź
		) <=> ż
		* <=> ć
		/ <=> ę
		; <=> ł
		q <=> ó
		~ <=> ń
```

	Hence, the charmap of the Polish version is:

```
		0020	 !ą#$ś&'źżć+,-.ę
		0030	0123456789:ł<=>?
		0040	@ABCDEFGHIJKLMNO
		0050	PQRSTUVWXYZ[\]^_
		0060	´abcdefghijklmno
		0070	pórstuvwxyz{|}ń 
		0080	ÀÁÂÄÆÇÈÉÊËÌÍÎÏÒÓ
		0090	ÔÖÙÚÛÜßàáâäæçèéê
		00A0	ëìíîïòóôöùúûüÑñ¿
		00B0	¡
		```

Kanji.dat
=========

Files
- C:\GTA2\data\kanji.dat

These files contain the implemented Japanese glyphs.

File structure
--------------

```
<header>
<section>
<section>
...
```

Header
------

```
char[3]	"KAN"
char[1]	"J" (Language)
int16	64 00 (version = 100)
```

Section
-------

```
char[4]	<section type name>, "KIDX" or "KBIT"
int32	length of <section content>
```
Section type: KIDX (index of Kanji characters)
----------------------------------------------

This sections always has a length of 0x20000.

The index works as follows:

```
                *2                      read                    *32                    render
Shift-JIS 81 5B  →  IDX Offset 01 02 B6   →  IDX Contents 78 00  →  BIT Index 00 0F 00   →   16x16 Glyph ー
Shift-JIS 82 CC  →  IDX Offset 01 05 98   →  IDX Contents E9 01  →  BIT Index 00 3D 20   →   16x16 Glyph の
Shift-JIS 83 4E  →  IDX Offset 01 06 9C   →  IDX Contents 6B 02  →  BIT Index 00 4D 60   →   16x16 Glyph ク
Shift-JIS 83 8C  →  IDX Offset 01 07 18   →  IDX Contents A9 02  →  BIT Index 00 55 20   →   16x16 Glyph レ
Shift-JIS 83 8D  →  IDX Offset 01 07 1A   →  IDX Contents AA 02  →  BIT Index 00 55 40   →   16x16 Glyph ロ
```

See also:
- [Implemented glyphs](https://misc.daniel-marschall.de/spiele/gta1/kanji_valid.txt)
- [All glyphs as PNG](https://misc.daniel-marschall.de/spiele/gta1/files/GTADATA/KANJI_BIT.PNG) (16x80640 image might be displayed wrong in the browser)
- [List of all Shift-JIS code points](https://misc.daniel-marschall.de/spiele/gta1/shift_jis.txt)

Section type: KBIT (glyphs)
---------------------------

Each glyph has a size of 16x16 pixels and takes 32 bytes.
The encoding is raw, 1 bit per pixel.
