class WorkoutBlock {
  final String type; // tabata | circuito | emom | series
  final List<Map<String, dynamic>> exercises;

  // Configuración flexible
  final int? work;
  final int? rest;
  final int? rounds;
  final int? time; // EMOM
  final int? series;
  final int? reps;
  final String? weight;

  WorkoutBlock({
    required this.type,
    required this.exercises,
    this.work,
    this.rest,
    this.rounds,
    this.time,
    this.series,
    this.reps,
    this.weight,
  });

  Map<String, dynamic> toMap() => {
        "type": type,
        "exercises": exercises,
        if (work != null) "work": work,
        if (rest != null) "rest": rest,
        if (rounds != null) "rounds": rounds,
        if (time != null) "time": time,
        if (series != null) "series": series,
        if (reps != null) "reps": reps,
        if (weight != null) "weight": weight,
      };

  factory WorkoutBlock.fromMap(Map<String, dynamic> map) {
    return WorkoutBlock(
      type: map["type"],
      exercises: List<Map<String, dynamic>>.from(map["exercises"]),
      work: map["work"],
      rest: map["rest"],
      rounds: map["rounds"],
      time: map["time"],
      series: map["series"],
      reps: map["reps"],
      weight: map["weight"],
    );
  }
}
