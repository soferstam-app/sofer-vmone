import 'dart:async';
import 'package:flutter/material.dart';
import 'models.dart';
import 'settings_screen.dart';
import 'storage_service.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'summary_screen.dart';

class SoferHome extends StatefulWidget {
  const SoferHome({super.key});

  @override
  State<SoferHome> createState() => _SoferHomeState();
}

class _SoferHomeState extends State<SoferHome> {
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  DateTime? _timerStartTime;
  DateTime? _timerEndTime;

  List<Project> projects = [];
  List<WorkSession> history = [];
  Duration _lastSessionTime = Duration.zero;
  final StorageService _storageService = StorageService();

  // בקרים לטפסים
  Project? _selectedProject;
  final _pageCtrl = TextEditingController();
  final _lineFromCtrl = TextEditingController();
  final _lineToCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _mezuzaLineCtrl = TextEditingController();

  // להזנה ידנית
  DateTime? _manualDate;
  TimeOfDay _manualStartTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _manualEndTime = const TimeOfDay(hour: 10, minute: 0);
  bool _manualIncludeTime = true; // האם לכלול חישוב זמן בהזנה ידנית

  // להזנת תפילין מפורטת
  String _tefillinMode = 'set'; // set, head, hand, parshiya
  String _tefillinPartType = 'head'; // head, hand
  int _tefillinParshiyaIndex = 1; // 1..4

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final loadedProjects = await _storageService.loadProjects();
      final loadedHistory = await _storageService.loadHistory();
      setState(() {
        projects = loadedProjects;
        history = loadedHistory;
      });
    } catch (e) {
      debugPrint("Error loading data: $e");
    }
  }

  // --- גימטריה ---
  int _gematriaDecode(String str) {
    if (str.isEmpty) return 0;
    // ניקוי גרשיים ורווחים
    str = str.replaceAll("'", "").replaceAll('"', "").trim();

    final Map<String, int> letters = {
      'א': 1,
      'b': 2,
      'ב': 2,
      'ג': 3,
      'ד': 4,
      'ה': 5,
      'ו': 6,
      'ז': 7,
      'ח': 8,
      'ט': 9,
      'י': 10,
      'כ': 20,
      'ך': 20,
      'ל': 30,
      'מ': 40,
      'ם': 40,
      'נ': 50,
      'ן': 50,
      'ס': 60,
      'ע': 70,
      'פ': 80,
      'ף': 80,
      'צ': 90,
      'ץ': 90,
      'ק': 100,
      'r': 200,
      'ר': 200,
      'ש': 300,
      'ת': 400,
    };

    int sum = 0;
    for (int i = 0; i < str.length; i++) {
      sum += letters[str[i]] ?? 0;
    }
    return sum;
  }

  // --- המרת תאריך לעברי ---
  String _getHebrewDate(DateTime date) {
    final jewishDate = JewishDate.fromDateTime(date);
    final formatter = HebrewDateFormatter()..hebrewFormat = true;
    return formatter.format(jewishDate);
  }

  // --- ניהול טיימר ---
  void _toggleTimer() {
    setState(() {
      if (_stopwatch.isRunning) {
        _stopwatch.stop();
        _timer?.cancel();
        _timerEndTime = DateTime.now();
        _lastSessionTime = _stopwatch.elapsed;
        _stopwatch.reset();

        // פתיחת הדיאלוג במצב "טיימר"
        _openEntryDialog(isManual: false);
      } else {
        _timerStartTime = DateTime.now();
        _stopwatch.start();
        _timer = Timer.periodic(
          const Duration(seconds: 1),
          (t) => setState(() {}),
        );
      }
    });
  }

  // --- דיאלוג ראשי (משמש גם לטיימר וגם לידני) ---
  void _openEntryDialog({required bool isManual}) {
    // איפוס שדות
    _selectedProject = null;
    _pageCtrl.clear();
    _lineFromCtrl.clear();
    _lineToCtrl.clear();
    _amountCtrl.clear();
    _mezuzaLineCtrl.clear();
    _manualDate = DateTime.now();
    _manualStartTime = const TimeOfDay(hour: 9, minute: 0);
    _manualEndTime = const TimeOfDay(hour: 10, minute: 0);
    _manualIncludeTime = true;
    _tefillinMode = 'set';
    _tefillinPartType = 'head';
    _tefillinParshiyaIndex = 1;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isManual ? "הזנה ידנית" : "סיכום כתיבה"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // תצוגת זמן / בחירת זמן לידני
                    if (!isManual)
                      Text(
                        "זמן עבודה: ${_formatTime(_lastSessionTime)}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      )
                    else
                      _buildManualTimePicker(setDialogState),

                    const SizedBox(height: 15),

                    // בחירת פרויקט
                    if (projects.isEmpty)
                      const Text(
                        "אין פרויקטים. צור פרויקט בהגדרות.",
                        style: TextStyle(color: Colors.red),
                      )
                    else
                      DropdownButton<Project>(
                        hint: const Text("בחר פרויקט"),
                        value: _selectedProject,
                        isExpanded: true,
                        items: projects
                            .map(
                              (p) => DropdownMenuItem(
                                value: p,
                                child: Text(p.name),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          setDialogState(() => _selectedProject = val);
                        },
                      ),

                    const SizedBox(height: 10),
                    // טופס דינמי
                    if (_selectedProject != null)
                      _buildDynamicForm(_selectedProject!, setDialogState),
                  ],
                ),
              ),
              actions: [
                // כפתור מחיקה/ביטול
                TextButton(
                  onPressed: () {
                    // אם זה היה טיימר, הזמן נמחק כפי שביקשת
                    Navigator.pop(context);
                  },
                  child: const Text(
                    "מחיקה / ביטול",
                    style: TextStyle(color: Colors.red),
                  ),
                ),

                // כפתור הוסף (רק שומר ומנקה שדות, לא סוגר)
                ElevatedButton(
                  onPressed: _selectedProject == null
                      ? null
                      : () async {
                          if (await _validateAndSave(context, isManual)) {
                            // מנקה את השדות להזנה נוספת
                            _pageCtrl.clear();
                            _lineFromCtrl.clear();
                            _lineToCtrl.clear();
                            _amountCtrl.clear();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "נוסף! ניתן להזין עוד נתונים לאותו זמן.",
                                ),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey,
                  ),
                  child: const Text("הוסף"),
                ),

                // כפתור אישור (שומר וסוגר)
                ElevatedButton(
                  onPressed: _selectedProject == null
                      ? null
                      : () async {
                          if (await _validateAndSave(context, isManual)) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("הנתונים נשמרו בהצלחה!"),
                              ),
                            );
                          }
                        },
                  child: const Text("אישור וסגירה"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildManualTimePicker(StateSetter setDialogState) {
    return Column(
      children: [
        SwitchListTile(
          title: const Text("חישוב זמן כתיבה"),
          value: _manualIncludeTime,
          onChanged: (val) {
            setDialogState(() => _manualIncludeTime = val);
          },
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        if (_manualIncludeTime)
          Row(
            children: [
              const Text("התחלה: "),
              TextButton(
                onPressed: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: _manualStartTime,
                  );
                  if (t != null) {
                    setDialogState(() => _manualStartTime = t);
                  }
                },
                child: Text(_manualStartTime.format(context)),
              ),
              const Spacer(),
              const Text("סיום: "),
              TextButton(
                onPressed: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: _manualEndTime,
                  );
                  if (t != null) {
                    setDialogState(() => _manualEndTime = t);
                  }
                },
                child: Text(_manualEndTime.format(context)),
              ),
            ],
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Text("תאריך: "),
            TextButton(
              onPressed: () async {
                await _showHebrewDatePickerDialog(setDialogState);
              },
              child: Text(
                _manualDate == null
                    ? "ללא תאריך (כללי)"
                    : _getHebrewDate(_manualDate!),
              ),
            ),
            if (_manualDate != null)
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => setDialogState(() => _manualDate = null),
              ),
          ],
        ),
      ],
    );
  }

  // --- דיאלוג בחירת תאריך עברי ---
  Future<void> _showHebrewDatePickerDialog(StateSetter setParentState) async {
    // אתחול תאריך נוכחי (או שנבחר כבר)
    DateTime currentGregorian = _manualDate ?? DateTime.now();
    JewishDate jewishDate = JewishDate.fromDateTime(currentGregorian);

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            int currentYear = jewishDate.getJewishYear();
            int currentMonth = jewishDate.getJewishMonth();
            int currentDay = jewishDate.getJewishDayOfMonth();
            bool isLeap = jewishDate.isJewishLeapYear();
            int daysInMonth = jewishDate.getDaysInJewishMonth();

            // רשימת שנים (נוכחית +/- 10)
            List<int> years = List.generate(21, (i) => (currentYear - 10) + i);

            // רשימת חודשים - מתחיל מתשרי (7)
            List<int> months;
            if (isLeap) {
              months = [7, 8, 9, 10, 11, 12, 13, 1, 2, 3, 4, 5, 6];
            } else {
              months = [7, 8, 9, 10, 11, 12, 1, 2, 3, 4, 5, 6];
            }

            // רשימת ימים (לפי מספר הימים בחודש הנוכחי)
            List<int> days = List.generate(daysInMonth, (i) => i + 1);

            return AlertDialog(
              title: const Text("בחר תאריך עברי"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // שנה
                  DropdownButton<int>(
                    value: years.contains(currentYear) ? currentYear : years[0],
                    items: years.map((y) {
                      // המרת מספר שנה לאותיות (פשוטה) או הצגה כמספר
                      return DropdownMenuItem(
                          value: y, child: Text(_formatHebrewYear(y)));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        // בדיקת שנה מעוברת והתאמת חודש אם צריך (אדר ב -> אדר)
                        JewishDate temp = JewishDate();
                        temp.setJewishDate(val, 1, 1);
                        bool newIsLeap = temp.isJewishLeapYear();

                        int newMonth = currentMonth;
                        if (!newIsLeap && currentMonth == 13) {
                          newMonth = 12;
                        }

                        // שמירה על היום בחודש אם אפשר
                        temp.setJewishDate(val, newMonth, 1);
                        int maxDays = temp.getDaysInJewishMonth();
                        int newDay =
                            currentDay > maxDays ? maxDays : currentDay;

                        jewishDate.setJewishDate(val, newMonth, newDay);
                        setState(() {});
                      }
                    },
                  ),
                  // חודש
                  DropdownButton<int>(
                    value: months.contains(currentMonth) ? currentMonth : 1,
                    items: months.map((m) {
                      return DropdownMenuItem(
                        value: m,
                        child: Text(_getHebrewMonthName(m, isLeap)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        // בדיקת ימים בחודש החדש ושמירה על היום אם אפשר
                        jewishDate.setJewishDate(currentYear, val, 1);
                        int maxDays = jewishDate.getDaysInJewishMonth();
                        int newDay =
                            currentDay > maxDays ? maxDays : currentDay;

                        jewishDate.setJewishDate(currentYear, val, newDay);
                        setState(() {});
                      }
                    },
                  ),
                  // יום
                  DropdownButton<int>(
                    value: days.contains(currentDay) ? currentDay : 1,
                    items: days.map((d) {
                      return DropdownMenuItem(
                          value: d, child: Text(_formatHebrewNumber(d)));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        jewishDate.setJewishDate(
                            currentYear, currentMonth, val);
                        setState(() {});
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("ביטול"),
                ),
                ElevatedButton(
                  onPressed: () {
                    setParentState(() {
                      _manualDate = jewishDate.getGregorianCalendar();
                    });
                    Navigator.pop(context);
                  },
                  child: const Text("בחר"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatHebrewYear(int year) {
    // פורמט פשוט להצגת השנה (למשל 5784 -> תשפ"ד)
    // שימוש ב-HebrewDateFormatter של הספרייה
    final formatter = HebrewDateFormatter()..hebrewFormat = true;
    // ניצור תאריך פיקטיבי באותה שנה כדי לפרמט את השנה
    final tempDate = JewishDate();
    tempDate.setJewishDate(year, 1, 1);
    // הפורמט מחזיר מחרוזת מלאה, נחלץ את השנה או נשתמש במספר אם מסובך
    // לצורך הפשטות נציג את המספר והמשתמש יבין, או נשתמש בפורמט מלא
    return formatter.format(tempDate).split(' ').last;
  }

  String _getHebrewMonthName(int monthIndex, bool isLeap) {
    // המרה ידנית פשוטה לשמות חודשים כדי לשלוט בתצוגה
    const months = [
      "ניסן",
      "אייר",
      "סיון",
      "תמוז",
      "אב",
      "אלול",
      "תשרי",
      "חשון",
      "כסלו",
      "טבת",
      "שבט"
    ];

    if (monthIndex <= 6) return months[monthIndex - 1]; // ניסן-אלול
    if (monthIndex >= 7 && monthIndex <= 11)
      return months[monthIndex - 1]; // תשרי-שבט

    // אדרים
    if (isLeap) {
      if (monthIndex == 12) return "אדר א'";
      if (monthIndex == 13) return "אדר ב'";
    } else {
      if (monthIndex == 12) return "אדר";
    }
    return "";
  }

  String _formatHebrewNumber(int n) {
    if (n > 30) return n.toString();
    const ones = ["", "א", "ב", "ג", "ד", "ה", "ו", "ז", "ח", "ט"];

    if (n == 15) return "טו";
    if (n == 16) return "טז";
    if (n < 10) return ones[n];
    if (n == 10) return "י";
    if (n < 20) return "י${ones[n % 10]}";
    if (n == 20) return "כ";
    if (n < 30) return "כ${ones[n % 10]}";
    if (n == 30) return "ל";
    return n.toString();
  }

  Widget _buildDynamicForm(Project p, StateSetter setDialogState) {
    if (p.type == ProjectType.sefer) {
      return Column(
        children: [
          TextField(
            controller: _pageCtrl,
            decoration: const InputDecoration(
              labelText: "עמוד (למשל: יא)",
              hintText: "אותיות או מספרים",
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _lineFromCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "משורה"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _lineToCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "עד שורה"),
                ),
              ),
            ],
          ),
        ],
      );
    } else if (p.type == ProjectType.mezuza) {
      return Column(
        children: [
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: "כמות מזוזות"),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _mezuzaLineCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "עד שורה (אופציונלי)",
              hintText: "השאר ריק למזוזה שלמה",
            ),
          ),
        ],
      );
    } else {
      // תפילין
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButton<String>(
            value: _tefillinMode,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'set', child: Text("סט שלם (ראש+יד)")),
              DropdownMenuItem(
                value: 'head',
                child: Text("תפילין של ראש (4 פרשיות)"),
              ),
              DropdownMenuItem(
                value: 'hand',
                child: Text("תפילין של יד (4 פרשיות)"),
              ),
              DropdownMenuItem(
                value: 'parshiya',
                child: Text("פרשייה בודדת (ראש/יד)"),
              ),
            ],
            onChanged: (v) => setDialogState(() => _tefillinMode = v!),
          ),
          const SizedBox(height: 10),
          if (_tefillinMode == 'parshiya') ...[
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    value: _tefillinPartType,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: 'head',
                        child: Text("תפילין של ראש"),
                      ),
                      DropdownMenuItem(
                        value: 'hand',
                        child: Text("תפילין של יד"),
                      ),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => _tefillinPartType = v!),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButton<int>(
                    value: _tefillinParshiyaIndex,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 1, child: Text("1. קדש")),
                      DropdownMenuItem(
                        value: 2,
                        child: Text("2. והיה כי יביאך"),
                      ),
                      DropdownMenuItem(value: 3, child: Text("3. שמע")),
                      DropdownMenuItem(
                        value: 4,
                        child: Text("4. והיה אם שמוע"),
                      ),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => _tefillinParshiyaIndex = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _mezuzaLineCtrl, // שימוש חוזר בבקר שורות
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: "עד שורה (השאר ריק לפרשייה מלאה)",
                hintText:
                    _tefillinPartType == 'head' ? "עד 4 שורות" : "עד 7 שורות",
              ),
            ),
          ] else ...[
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "כמות יחידות"),
            ),
          ],
        ],
      );
    }
  }

  // --- לוגיקת שמירה וולידציה ---
  Future<bool> _validateAndSave(
    BuildContext dialogContext,
    bool isManual,
  ) async {
    // 1. חישוב זמן
    DateTime sessionStart;
    DateTime sessionEnd;

    if (isManual) {
      final date = _manualDate ?? DateTime.now();
      if (_manualIncludeTime) {
        sessionStart = DateTime(
          date.year,
          date.month,
          date.day,
          _manualStartTime.hour,
          _manualStartTime.minute,
        );
        sessionEnd = DateTime(
          date.year,
          date.month,
          date.day,
          _manualEndTime.hour,
          _manualEndTime.minute,
        );
        if (sessionEnd.isBefore(sessionStart)) {
          sessionEnd =
              sessionEnd.add(const Duration(days: 1)); // הנחה שעבר חצות
        }
      } else {
        // ללא זמן - נקבע התחלה וסוף לאותו זמן (משך 0)
        sessionStart = DateTime(date.year, date.month, date.day);
        sessionEnd = sessionStart;
      }
    } else {
      sessionStart = _timerStartTime ?? DateTime.now();
      sessionEnd = _timerEndTime ?? DateTime.now();
    }

    if (_selectedProject == null) return false;

    // 2. המרת נתונים
    int amount = 0;
    int startLine = 0;
    int endLine = 0;
    String desc = "";
    String? tefillinType;
    int? parshiya;

    if (_selectedProject!.type == ProjectType.sefer) {
      // המרת עמוד מאותיות למספרים
      String pageInput = _pageCtrl.text;
      int pageNum = int.tryParse(pageInput) ?? _gematriaDecode(pageInput);
      startLine = int.tryParse(_lineFromCtrl.text) ?? 0;
      endLine = int.tryParse(_lineToCtrl.text) ?? 0;

      // ולידציות ספר
      if (pageNum == 0 || startLine == 0 || endLine == 0) {
        _showError(dialogContext, "יש להזין עמוד ושורות תקינים");
        return false;
      }
      if (_selectedProject!.totalPages != null &&
          pageNum > _selectedProject!.totalPages!) {
        _showError(
          dialogContext,
          "מספר העמוד חורג מהגדרת הספר (${_selectedProject!.totalPages})",
        );
        return false;
      }
      if (_selectedProject!.linesPerPage != null &&
          (startLine > _selectedProject!.linesPerPage! ||
              endLine > _selectedProject!.linesPerPage!)) {
        _showError(
          dialogContext,
          "מספר השורות חורג מהגדרת העמוד (${_selectedProject!.linesPerPage})",
        );
        return false;
      }
      if (startLine > endLine) {
        _showError(dialogContext, "שורה התחלה חייבת להיות קטנה משורה סיום");
        return false;
      }

      // בדיקת חפיפה (Overlap)
      bool hasOverlap = _checkOverlap(
        _selectedProject!.id,
        pageNum,
        startLine,
        endLine,
      );
      if (hasOverlap) {
        // כאן רק מתריעים למשתמש אבל מאפשרים שמירה (כמו שביקשת)
        bool confirm = await showDialog(
              context: dialogContext,
              builder: (c) => AlertDialog(
                title: const Text("שים לב: כפילות"),
                content: const Text(
                  "חלק מהשורות בעמוד זה כבר נכתבו בעבר. האם לשמור בכל זאת?",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text("ביטול"),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text("שמור בכל זאת"),
                  ),
                ],
              ),
            ) ??
            false;
        if (!confirm) return false;
      }

      amount = pageNum; // בספר ה-amount הוא מספר העמוד
      desc = "עמוד $pageInput ($startLine-$endLine)";
    } else {
      // מזוזה / תפילין
      if (_selectedProject!.type == ProjectType.tefillin &&
          _tefillinMode == 'parshiya') {
        // טיפול בפרשייה בודדת (ללא שדה כמות)
        amount = 1;
        endLine = int.tryParse(_mezuzaLineCtrl.text) ?? 0;

        tefillinType = _tefillinPartType;
        parshiya = _tefillinParshiyaIndex;

        int maxLines = _tefillinPartType == 'head' ? 4 : 7;
        if (endLine > maxLines) {
          _showError(
            dialogContext,
            "בתפילין ${_tefillinPartType == 'head' ? 'של ראש' : 'של יד'} יש עד $maxLines שורות",
          );
          return false;
        }

        String part = _tefillinPartType == 'head' ? "ראש" : "יד";
        String parshiyaName = "";
        switch (_tefillinParshiyaIndex) {
          case 1:
            parshiyaName = "קדש";
            break;
          case 2:
            parshiyaName = "והיה כי יביאך";
            break;
          case 3:
            parshiyaName = "שמע";
            break;
          case 4:
            parshiyaName = "והיה אם שמוע";
            break;
        }
        desc = "פרשיית $parshiyaName של $part";
        if (endLine > 0) desc += " (עד שורה $endLine)";
      } else {
        // טיפול רגיל (מזוזה או סט תפילין)
        amount = int.tryParse(_amountCtrl.text) ?? 0;
        if (amount == 0) {
          _showError(dialogContext, "יש להזין כמות");
          return false;
        }

        if (_selectedProject!.type == ProjectType.mezuza) {
          int line = int.tryParse(_mezuzaLineCtrl.text) ?? 0;
          if (line > 22) {
            _showError(dialogContext, "במזוזה יש רק 22 שורות");
            return false;
          }
          endLine = line;
          if (line > 0) {
            desc = "$amount מזוזות (עד שורה $line)";
          } else {
            desc = "$amount מזוזות";
          }
        } else {
          // תפילין (סט/ראש/יד)
          if (_tefillinMode == 'set') {
            desc = "$amount סטים של תפילין";
          } else if (_tefillinMode == 'head') {
            desc = "$amount תפילין של ראש";
            tefillinType = 'head';
          } else if (_tefillinMode == 'hand') {
            desc = "$amount תפילין של יד";
            tefillinType = 'hand';
          } else {
            desc = "$amount יחידות";
          }
        }
      }
    }

    // 3. שמירה
    setState(() {
      history.add(
        WorkSession(
          id: DateTime.now().toString(),
          projectId: _selectedProject!.id,
          startTime: sessionStart,
          endTime: sessionEnd,
          amount: amount,
          startLine: startLine,
          endLine: endLine,
          tefillinType: tefillinType,
          parshiya: parshiya,
          description: desc,
          isManual: isManual,
        ),
      );
      _storageService.saveHistory(history);
    });

    return true;
  }

  // פונקציית בדיקת חפיפה פשוטה
  bool _checkOverlap(String projId, int page, int start, int end) {
    for (var session in history) {
      if (session.projectId == projId && session.amount == page) {
        // בדיקה אם הטווחים חופפים
        // חפיפה קורית אם ההתחלה החדשה היא לפני הסוף הישן, והסוף החדש הוא אחרי ההתחלה הישנה
        if (start <= session.endLine && end >= session.startLine) {
          return true;
        }
      }
    }
    return false;
  }

  void _showError(BuildContext ctx, String msg) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.red)),
      ),
    );
  }

  String _formatTime(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(d.inHours)}:${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
  }

  // איפוס מלא של הנתונים
  void _resetAllData() async {
    await _storageService.saveProjects([]);
    await _storageService.saveHistory([]);
    setState(() {
      projects = [];
      history = [];
    });
  }

  void _navigateToSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          projects: projects,
          onProjectAdded: (p) {
            setState(() => projects.add(p));
            _storageService.saveProjects(projects);
          },
          onProjectUpdated: (p) {
            setState(() {
              int index = projects.indexWhere((element) => element.id == p.id);
              if (index != -1) projects[index] = p;
            });
            _storageService.saveProjects(projects);
          },
          onProjectDeleted: (p) {
            setState(
              () {
                projects.removeWhere((element) => element.id == p.id);
                history.removeWhere((session) => session.projectId == p.id);
              },
            );
            _storageService.saveProjects(projects);
            _storageService.saveHistory(history);
          },
          onResetAllData: _resetAllData,
        ),
      ),
    );
  }

  void _navigateToSummary() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SummaryScreen(
          projects: projects,
          history: history,
          onHistoryUpdated: (updatedHistory) {
            setState(() => history = updatedHistory);
            _storageService.saveHistory(history);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF7FF),
      appBar: AppBar(title: const Text('יומן סופר סת"ם'), centerTitle: true),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // תאריך עברי (סטטי כרגע, אפשר לחבר לספריית המרות בהמשך)
            Text(
              _getHebrewDate(DateTime.now()),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 30),

            // טיימר
            Text(
              _formatTime(_stopwatch.elapsed),
              style: const TextStyle(fontSize: 80, fontWeight: FontWeight.w200),
            ),
            const SizedBox(height: 40),

            ElevatedButton.icon(
              onPressed: _toggleTimer,
              icon: Icon(_stopwatch.isRunning ? Icons.stop : Icons.play_arrow),
              label: Text(_stopwatch.isRunning ? "סיום כתיבה" : "תחילת כתיבה"),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _stopwatch.isRunning ? Colors.red[400] : Colors.green[400],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 50,
                  vertical: 25,
                ),
                textStyle: const TextStyle(fontSize: 20),
              ),
            ),

            const SizedBox(height: 30),

            // כפתור הזנה ידנית
            OutlinedButton.icon(
              onPressed: () => _openEntryDialog(isManual: true),
              icon: const Icon(Icons.edit_calendar),
              label: const Text("הוספת כתיבה ידנית (ללא טיימר)"),
            ),

            const SizedBox(height: 20),
            if (history.isNotEmpty)
              Text(
                "נשמרו ${history.length} רשומות בסשן זה",
                style: const TextStyle(color: Colors.grey),
              ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: "סיכומים",
          ),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: "הגדרות"),
        ],
        onTap: (index) {
          if (index == 0) _navigateToSummary();
          if (index == 1) _navigateToSettings();
        },
      ),
    );
  }
}
