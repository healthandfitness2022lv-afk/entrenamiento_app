import 'package:flutter/material.dart';

class SeriesBlockWidget extends StatelessWidget {
  final int index;
  final Map<String, dynamic> block;
  final bool expanded;
  final void Function(int blockIndex, String exercise, bool value)
    onPerSideChanged;

  final Map<String, List<Map<String, dynamic>>> seriesData;
  final Map<String, List<TextEditingController>> seriesRepsCtrl;
  final Map<String, List<TextEditingController>> seriesWeightCtrl;

  final String Function(dynamic) normalizeExerciseName;
  final String? Function(Map<String, dynamic>) getEquipment;
  final bool Function(Map<String, dynamic>) isPerSide;

  final void Function(Map<String, dynamic>) onInfoPressed;
  final void Function(int, String) onDeleteExercise;
  final void Function(int) onAddExercise;
  final VoidCallback onStateChanged;


  final Widget Function(String, int) suggestedWeightText;
  final Widget Function(String, double) suggestedRepsText;

  const SeriesBlockWidget({
    super.key,
    required this.index,
    required this.block,
    required this.expanded,
    required this.seriesData,
    required this.seriesRepsCtrl,
    required this.seriesWeightCtrl,
    required this.normalizeExerciseName,
    required this.getEquipment,
    required this.isPerSide,
    required this.onInfoPressed,
    required this.onDeleteExercise,
    required this.onAddExercise,
    required this.suggestedWeightText,
    required this.suggestedRepsText,
    required this.onStateChanged,
    required this.onPerSideChanged,

  });

  @override
  Widget build(BuildContext context) {
    if (!expanded) return const SizedBox();

    return Column(
      children: [
        for (final ex in block['exercises'])
          _buildExercise(context, ex),

        const SizedBox(height: 16),

        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text("Agregar ejercicio"),
            onPressed: () => onAddExercise(index),
          ),
        ),
      ],
    );
  }

  Widget _buildExercise(BuildContext context, Map<String, dynamic> ex) {
    final String name = normalizeExerciseName(ex['name']);
    final String key = "$index-$name";

    if (!seriesData.containsKey(key) ||
        seriesData[key]!.isEmpty ||
        !seriesRepsCtrl.containsKey(key) ||
        !seriesWeightCtrl.containsKey(key)) {
      return const SizedBox();
    }

    final bool isTimeBased =
        seriesData[key]![0]['valueType'] == 'time';

    return Column(
      children: [
        const SizedBox(height: 12),
        

        Row(
          children: [
            Expanded(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
  children: [
    Expanded(
      child: Text(
        name,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    ),

    SizedBox(
      width: 22,
      height: 22,
      child: Checkbox(
        value: isPerSide(ex),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onChanged: (v) {
          onPerSideChanged(index, name, v == true);
        },
      ),
    ),

    const SizedBox(width: 4),

    const Text(
      "L",
      style: TextStyle(fontSize: 12),
    ),
  ],
),

      if (getEquipment(ex) != null)
        Text(
          getEquipment(ex)!,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),

      const SizedBox(height: 4),

      // 🔥 SUGERENCIA DE PESO
      suggestedWeightText(
        name,
        seriesRepsCtrl[key]![0].text.isNotEmpty
            ? int.tryParse(seriesRepsCtrl[key]![0].text) ?? 0
            : 0,
      ),

      const SizedBox(height: 2),

      // 🔥 SUGERENCIA DE REPS
      suggestedRepsText(
        name,
        seriesWeightCtrl[key]![0].text.isNotEmpty
            ? double.tryParse(seriesWeightCtrl[key]![0].text) ?? 0
            : 0,
      ),
    ],
  ),
),

            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () => onInfoPressed(ex),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => onDeleteExercise(index, name),
            ),
          ],
        ),
        

        const SizedBox(height: 8),

        Table(
          columnWidths: const {
            0: FixedColumnWidth(50),
            1: FlexColumnWidth(),
            2: FlexColumnWidth(),
            3: FlexColumnWidth(),
            4: FixedColumnWidth(40),
          },
          children: [
            TableRow(
              children: [
                const Padding(
                  padding: EdgeInsets.all(4),
                  child: Text("Serie"),
                ),
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(isTimeBased ? "Tiempo (s)" : "Reps"),
                ),
                const Padding(
                  padding: EdgeInsets.all(4),
                  child: Text("Peso"),
                ),
                const Padding(
                  padding: EdgeInsets.all(4),
                  child: Text("RPE"),
                ),
                const Padding(
                  padding: EdgeInsets.all(4),
                  child: Text("✔"),
                ),
              ],
            ),

            for (int i = 0; i < seriesData[key]!.length; i++)
              _buildRow(context, key, name, i),
          ],
        ),
        const SizedBox(height: 8),

Row(
  mainAxisAlignment: MainAxisAlignment.end,
  children: [
    IconButton(
      icon: const Icon(Icons.remove_circle_outline),
      onPressed: () {
        if (seriesData[key]!.length > 1) {
          seriesData[key]!.removeLast();
          seriesRepsCtrl[key]!.removeLast();
          seriesWeightCtrl[key]!.removeLast();
          onStateChanged();
        }
      },
    ),
    IconButton(
      icon: const Icon(Icons.add_circle_outline),
      onPressed: () {
        seriesData[key]!.add({
          'rpe': 7,
          'done': false,
          'valueType': seriesData[key]![0]['valueType'],
        });

        seriesRepsCtrl[key]!.add(TextEditingController());
        seriesWeightCtrl[key]!.add(TextEditingController());

        onStateChanged();
      },
    ),
  ],
),

      ],
    );
  }

  TableRow _buildRow(
    BuildContext context,
    String key,
    String name,
    int i,
  ) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(4),
          child: Text("${i + 1}"),
        ),

        Padding(
          padding: const EdgeInsets.all(4),
          child: TextField(
  controller: seriesRepsCtrl[key]![i],
  keyboardType: TextInputType.number,
  textInputAction: TextInputAction.done,
  onSubmitted: (_) {
    FocusScope.of(context).unfocus();
    onStateChanged();
  },
),

        ),

        Padding(
          padding: const EdgeInsets.all(4),
          child: TextField(
  controller: seriesWeightCtrl[key]![i],
  keyboardType: TextInputType.number,
  onSubmitted: (_) {
    FocusScope.of(context).unfocus();
    onStateChanged();
  },
),

        ),

        Padding(
          padding: const EdgeInsets.all(4),
          child: DropdownButton<int>(
            value: seriesData[key]![i]['rpe'],
            items: List.generate(
              10,
              (r) => DropdownMenuItem(
                value: r + 1,
                child: Text("${r + 1}"),
              ),
            ),
            onChanged: (v) {
  seriesData[key]![i]['rpe'] = v!;
  onStateChanged();
},

          ),
        ),

        Padding(
          padding: const EdgeInsets.all(4),
          child: Checkbox(
            value: seriesData[key]![i]['done'],
            onChanged: (v) {
  seriesData[key]![i]['done'] = v!;
  onStateChanged();
},

          ),
        ),
      ],
    );
    
  }
  
}
