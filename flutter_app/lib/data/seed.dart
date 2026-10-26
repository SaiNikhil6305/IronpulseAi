class Exercise {
  final String id;
  final String name;
  final String muscle;
  final String equipment;
  final String instructions;
  final bool custom;

  const Exercise(this.id, this.name, this.muscle, this.equipment, this.instructions, {this.custom = false});

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'muscle': muscle,
        'equipment': equipment,
        'instructions': instructions,
        'custom': custom ? 1 : 0,
      };

  factory Exercise.fromMap(Map<String, Object?> m) => Exercise(
        m['id'] as String,
        m['name'] as String,
        m['muscle'] as String,
        m['equipment'] as String,
        m['instructions'] as String,
        custom: (m['custom'] as int? ?? 0) == 1,
      );
}

const muscleLabels = <String, String>{
  'chest': 'Chest',
  'shoulders': 'Shoulders',
  'triceps': 'Triceps',
  'back': 'Back',
  'biceps': 'Biceps',
  'quads': 'Quads',
  'hamstrings': 'Hamstrings',
  'calves': 'Calves',
  'traps': 'Traps',
  'forearms': 'Forearms',
  'core': 'Abs & Core',
};

String muscleLabel(String key) => muscleLabels[key] ?? key;

/// Built-in library. Instructions are short written cues; no demo media is bundled
/// (only properly licensed media may be added later).
const seedExercises = <Exercise>[
  // Chest
  Exercise('bench', 'Barbell Bench Press', 'chest', 'Barbell',
      'Retract shoulder blades, lower the bar to mid-chest under control, press up. Use a spotter or safety pins for heavy sets.'),
  Exercise('incline-db', 'Incline Dumbbell Press', 'chest', 'Dumbbells',
      'Bench at 30-45°. Lower dumbbells to upper chest, press up and slightly in.'),
  Exercise('machine-chest', 'Machine Chest Press', 'chest', 'Machine',
      'Adjust seat so handles are at mid-chest. Press out without locking elbows hard.'),
  Exercise('cable-fly', 'Cable Fly', 'chest', 'Cable',
      'Slight bend in elbows, bring handles together in an arc, control the return.'),
  Exercise('pec-deck', 'Pec Deck Fly', 'chest', 'Machine', 'Keep chest up, squeeze the pads together, return slowly.'),
  Exercise('push-up', 'Push-Ups', 'chest', 'Bodyweight', 'Body in a straight line, lower chest to just above the floor, push up.'),
  // Shoulders
  Exercise('shoulder-press', 'Shoulder Press', 'shoulders', 'Dumbbells / Machine',
      'Brace core, press overhead without arching the lower back.'),
  Exercise('db-lateral', 'Dumbbell Lateral Raise', 'shoulders', 'Dumbbells',
      'Raise arms out to the side to shoulder height, lead with elbows, lower slowly.'),
  Exercise('cable-lateral', 'Cable Lateral Raise', 'shoulders', 'Cable', 'Single arm, raise to shoulder height, constant tension.'),
  Exercise('reverse-pec', 'Reverse Pec Deck', 'shoulders', 'Machine', 'Face the pad, open arms back to target rear delts.'),
  // Triceps
  Exercise('pushdown', 'Cable Pushdown', 'triceps', 'Cable', 'Elbows pinned to sides, extend fully, control the return.'),
  Exercise('overhead-ext', 'Overhead Cable Extension', 'triceps', 'Cable', 'Face away from the stack, extend overhead keeping elbows narrow.'),
  Exercise('db-ext', 'Dumbbell Extension', 'triceps', 'Dumbbells', 'Lower the dumbbell behind the head, extend up.'),
  Exercise('assisted-dip', 'Assisted Dips', 'triceps', 'Machine', 'Stay upright for triceps, lower to about 90° at the elbow.'),
  // Back
  Exercise('lat-pulldown', 'Lat Pulldown', 'back', 'Cable', 'Pull the bar to upper chest, drive elbows down, avoid leaning far back.'),
  Exercise('pull-up', 'Pull-Ups', 'back', 'Bodyweight', 'Full hang, pull until chin clears the bar, lower under control.'),
  Exercise('seated-row', 'Seated Cable Row', 'back', 'Cable', 'Chest tall, pull handle to stomach, squeeze shoulder blades.'),
  Exercise('chest-row', 'Chest-Supported Row', 'back', 'Machine / Dumbbells', 'Chest on the pad, row elbows back, pause at the top.'),
  Exercise('one-arm-row', 'One-Arm Dumbbell Row', 'back', 'Dumbbells', 'Hand and knee on bench, row dumbbell to hip.'),
  // Biceps
  Exercise('db-curl', 'Dumbbell Curl', 'biceps', 'Dumbbells', 'Elbows still, curl up, lower slowly.'),
  Exercise('hammer-curl', 'Hammer Curl', 'biceps', 'Dumbbells', 'Neutral grip, curl without swinging.'),
  Exercise('cable-curl', 'Cable Curl', 'biceps', 'Cable', 'Constant tension, full range of motion.'),
  Exercise('preacher-curl', 'Preacher Curl', 'biceps', 'Machine / EZ bar', 'Arms on the pad, avoid dropping fast at the bottom.'),
  // Legs
  Exercise('squat', 'Barbell Squat', 'quads', 'Barbell', 'Brace, sit down between hips, knees track over toes. Use safety bars.'),
  Exercise('leg-press', 'Leg Press', 'quads', 'Machine', 'Lower until knees near 90°, do not lock knees at the top.'),
  Exercise('leg-ext', 'Leg Extension', 'quads', 'Machine', 'Extend fully, squeeze quads, lower under control.'),
  Exercise('rdl', 'Romanian Deadlift', 'hamstrings', 'Barbell / Dumbbells', 'Hinge at hips with a neutral spine, bar close to legs.'),
  Exercise('leg-curl', 'Leg Curl', 'hamstrings', 'Machine', 'Curl heels toward glutes, control the return.'),
  Exercise('calf-raise', 'Calf Raise', 'calves', 'Machine / Bodyweight', 'Full stretch at the bottom, pause at the top.'),
  // Traps & forearms
  Exercise('shrug', 'Shrugs', 'traps', 'Dumbbells / Barbell', 'Lift shoulders straight up, pause, lower. No rolling.'),
  Exercise('farmer', "Farmer's Carry", 'forearms', 'Dumbbells', 'Walk tall holding heavy dumbbells. Log distance or time in reps.'),
  Exercise('wrist-curl', 'Wrist Curl', 'forearms', 'Dumbbells', 'Forearms on thighs, curl wrists up through full range.'),
  // Core
  Exercise('plank', 'Plank', 'core', 'Bodyweight', 'Straight line head to heels. Log seconds as reps.'),
  Exercise('cable-crunch', 'Cable Crunch', 'core', 'Cable', 'Kneel, crunch ribs toward hips, hips stay still.'),
  Exercise('knee-raise', 'Hanging Knee Raise', 'core', 'Bar', 'Hang, raise knees toward chest without swinging.'),
];
