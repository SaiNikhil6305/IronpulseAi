class SplitDay {
  String name;
  List<String> muscles;
  SplitDay(this.name, this.muscles);
  SplitDay copy() => SplitDay(name, [...muscles]);
}

class SplitTemplate {
  final String key;
  final String name;
  final String description;
  final List<SplitDay> days;
  const SplitTemplate(this.key, this.name, this.description, this.days);
}

List<SplitTemplate> splitTemplates() => [
      SplitTemplate('ppl', 'Push / Pull / Legs', 'Classic 3-day rotation. Run it 3 or 6 days a week.', [
        SplitDay('Push Day', ['chest', 'shoulders', 'triceps']),
        SplitDay('Pull Day', ['back', 'biceps', 'traps']),
        SplitDay('Leg Day', ['quads', 'hamstrings', 'calves']),
      ]),
      SplitTemplate('bro', 'Muscle-Group Days', 'One main muscle group per session.', [
        SplitDay('Chest', ['chest']),
        SplitDay('Back', ['back']),
        SplitDay('Shoulders', ['shoulders']),
        SplitDay('Arms', ['biceps', 'triceps']),
        SplitDay('Legs', ['quads', 'hamstrings', 'calves']),
        SplitDay('Abs & Core', ['core']),
      ]),
      SplitTemplate('ul', 'Upper / Lower', 'Alternate upper- and lower-body sessions.', [
        SplitDay('Upper Body', ['chest', 'back', 'shoulders', 'biceps', 'triceps']),
        SplitDay('Lower Body', ['quads', 'hamstrings', 'calves', 'core']),
      ]),
      SplitTemplate('full', 'Full Body', 'Several major muscle groups every session.', [
        SplitDay('Full Body A', ['chest', 'back', 'quads', 'shoulders']),
        SplitDay('Full Body B', ['back', 'hamstrings', 'chest', 'core']),
      ]),
      SplitTemplate('custom', 'Custom Split', 'Build your own days from scratch.', [
        SplitDay('Day 1', []),
      ]),
    ];
