import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/storage/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/units.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/widgets.dart';
import '../../notifications/data/notification_service.dart';
import '../../nutrition/data/nutrition_repository.dart';
import '../../profile/domain/profile.dart';

const goalOptions = {
  'build_muscle': 'Build muscle',
  'lose_fat': 'Lose body fat',
  'recomposition': 'Body recomposition',
  'strength': 'Improve strength',
  'endurance': 'Improve endurance',
  'consistency': 'Improve consistency',
  'maintain': 'Maintain current fitness',
};
const ageRanges = ['18-24', '25-34', '35-44', '45-54', '55-64', '65+'];
const equipmentOptions = {
  'full_gym': 'Full gym',
  'barbell': 'Barbell',
  'dumbbell': 'Dumbbells',
  'machine': 'Machines',
  'cable': 'Cables',
  'bodyweight': 'Bodyweight only',
  'bands': 'Resistance bands',
};
const dietOptions = {
  'vegetarian': 'Vegetarian',
  'eggetarian': 'Eggetarian',
  'vegan': 'Vegan',
  'non_vegetarian': 'Non-vegetarian',
  'lactose_free': 'Lactose-free',
  'gluten_free': 'Gluten-free',
};

/// Multi-step onboarding. Progress is saved after every step, so an
/// interrupted setup resumes where it stopped.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.editMode = false});
  final bool editMode;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _page = PageController();
  int _step = 0;
  bool _loaded = false;
  Map<String, dynamic> _p = Map.of(Profile.empty.json);
  bool _targetsOn = false;

  final _name = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _target = TextEditingController();
  final _allergies = TextEditingController();
  final _protein = TextEditingController();
  final _calories = TextEditingController();
  final _forms = List.generate(6, (_) => GlobalKey<FormState>());

  static const _steps = 6;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final db = ref.read(localDbProvider);
    final draft = await db.getDoc(Col.meta, Meta.onboardingDraft);
    final existing = await db.getDoc(Col.meta, Meta.profile);
    final base = {...Profile.empty.json, ...?existing, ...?(draft?['profile'] as Map?)?.cast<String, dynamic>()};
    final units = base['units'] as String?;
    setState(() {
      _p = base;
      _step = widget.editMode ? 0 : ((draft?['step'] as num?)?.toInt() ?? 0).clamp(0, _steps - 1);
      _name.text = (base['display_name'] as String?) ?? '';
      final h = (base['height_cm'] as num?)?.toDouble();
      _height.text = h == null ? '' : Units.trimNum(Units.isImperial(units) ? h / 2.54 : h, maxDecimals: 1);
      final w = (base['current_weight_kg'] as num?)?.toDouble();
      _weight.text = w == null ? '' : Units.trimNum(Units.fromKg(w, units), maxDecimals: 1);
      final t = (base['target_weight_kg'] as num?)?.toDouble();
      _target.text = t == null ? '' : Units.trimNum(Units.fromKg(t, units), maxDecimals: 1);
      _allergies.text = (base['allergies'] as String?) ?? '';
      _loaded = true;
    });
    if (_step > 0) WidgetsBinding.instance.addPostFrameCallback((_) => _page.jumpToPage(_step));
  }

  @override
  void dispose() {
    for (final c in [_name, _height, _weight, _target, _allergies, _protein, _calories]) {
      c.dispose();
    }
    _page.dispose();
    super.dispose();
  }

  bool get _imperial => _p['units'] == 'imperial';

  void _collect() {
    final units = _p['units'] as String?;
    final h = Validators.parseNum(_height.text);
    final w = Validators.parseNum(_weight.text);
    final t = Validators.parseNum(_target.text);
    _p['display_name'] = _name.text.trim();
    _p['height_cm'] = h == null ? null : (Units.isImperial(units) ? h * 2.54 : h);
    _p['current_weight_kg'] = w == null ? null : Units.toKg(w, units);
    _p['target_weight_kg'] = t == null ? null : Units.toKg(t, units);
    _p['allergies'] = _allergies.text.trim().isEmpty ? null : _allergies.text.trim();
  }

  Future<void> _saveDraft() async {
    _collect();
    await ref.read(localDbProvider).putDoc(Col.meta, Meta.onboardingDraft, {'step': _step, 'profile': _p});
  }

  Future<void> _next() async {
    if (!(_forms[_step].currentState?.validate() ?? true)) return;
    if (_step == 0 && _name.text.trim().isEmpty) return;
    if (_step < _steps - 1) {
      setState(() => _step++);
      await _saveDraft();
      await _page.animateToPage(_step, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      await _finish();
    }
  }

  Future<void> _back() async {
    if (_step == 0) return;
    setState(() => _step--);
    await _page.animateToPage(_step, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _finish() async {
    _collect();
    _p['timezone'] = ref.read(notificationServiceProvider).timezoneId;
    final profile = Profile(_p);
    await ref.read(profileRepositoryProvider).save(widget.editMode ? profile : profile.copyWith({'onboarding_completed': false}));
    if (_targetsOn) {
      await ref.read(nutritionRepositoryProvider).saveTargets(NutritionTargets(
            enabled: true,
            proteinG: Validators.parseNum(_protein.text),
            calories: Validators.parseNum(_calories.text),
          ));
    }
    await ref.read(localDbProvider).putDoc(Col.meta, Meta.onboardingDraft, {'step': _steps - 1, 'profile': _p});
    if (!mounted) return;
    if (widget.editMode) {
      showSnack(context, 'Profile saved.');
      context.pop();
    } else {
      context.go('/onboarding/split');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _step > 0 ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back) : null,
          title: Text(widget.editMode ? 'Edit profile' : 'Set up IronPulse'),
          actions: [Center(child: Padding(padding: const EdgeInsets.only(right: 16), child: Text('${_step + 1}/$_steps')))],
        ),
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gaps.lg),
              child: ProgressBar(value: (_step + 1) / _steps, height: 4),
            ),
            Expanded(
              child: PageView(
                controller: _page,
                physics: const NeverScrollableScrollPhysics(),
                children: [_basics(), _body(), _goals(), _training(), _equipment(), _nutrition()],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.sm, Gaps.lg, Gaps.lg),
              child: Row(children: [
                if (_step >= 1 && !widget.editMode && _step != 2)
                  Expanded(child: OutlinedButton(onPressed: _next, child: const Text('Skip'))),
                if (_step >= 1 && !widget.editMode && _step != 2) const SizedBox(width: Gaps.md),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _next,
                    child: Text(_step == _steps - 1 ? (widget.editMode ? 'Save' : 'Choose my split') : 'Continue'),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _stepBody({required String title, String? why, required List<Widget> children, required int index}) {
    return Form(
      key: _forms[index],
      child: ListView(
        padding: const EdgeInsets.all(Gaps.lg),
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          if (why != null) ...[
            const SizedBox(height: Gaps.sm),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline, size: 16, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(child: Text(why, style: const TextStyle(color: AppColors.textMuted, fontSize: 13))),
            ]),
          ],
          const SizedBox(height: Gaps.xl),
          ...children,
        ],
      ),
    );
  }

  Widget _chips<T>(Map<T, String> options, bool Function(T) selected, void Function(T) toggle) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in options.entries)
            FilterChip(label: Text(e.value), selected: selected(e.key), onSelected: (_) => setState(() => toggle(e.key))),
        ],
      );

  List<String> _list(String k) => [for (final v in (_p[k] as List? ?? const [])) '$v'];
  void _toggleIn(String k, String v) {
    final l = _list(k);
    l.contains(v) ? l.remove(v) : l.add(v);
    _p[k] = l;
  }

  Widget _basics() => _stepBody(index: 0, title: 'Welcome to IronPulse.\nLet\'s build your strongest self.', children: [
        TextFormField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'What should we call you?'),
          validator: (v) => Validators.required(v, field: 'Display name') ?? Validators.maxLength(60)(v),
        ),
        const SizedBox(height: Gaps.xl),
        const Text('Age range (optional)', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Used only to keep suggestions age-appropriate.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        const SizedBox(height: Gaps.sm),
        _chips<String>({for (final a in ageRanges) a: a}, (a) => _p['age_range'] == a,
            (a) => _p['age_range'] = _p['age_range'] == a ? null : a),
      ]);

  Widget _body() => _stepBody(
        index: 1,
        title: 'Your body stats',
        why: 'Optional. Used for your weight chart and goal progress. You can change these any time.',
        children: [
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'metric', label: Text('kg / cm')), ButtonSegment(value: 'imperial', label: Text('lb / in'))],
            selected: {_p['units'] as String? ?? 'metric'},
            onSelectionChanged: (s) => setState(() {
              _collect();
              _p['units'] = s.first;
              final u = s.first;
              final h = (_p['height_cm'] as num?)?.toDouble();
              _height.text = h == null ? '' : Units.trimNum(Units.isImperial(u) ? h / 2.54 : h, maxDecimals: 1);
              final w = (_p['current_weight_kg'] as num?)?.toDouble();
              _weight.text = w == null ? '' : Units.trimNum(Units.fromKg(w, u), maxDecimals: 1);
              final t = (_p['target_weight_kg'] as num?)?.toDouble();
              _target.text = t == null ? '' : Units.trimNum(Units.fromKg(t, u), maxDecimals: 1);
            }),
          ),
          const SizedBox(height: Gaps.lg),
          NumberField(
              controller: _height,
              label: 'Height',
              suffix: _imperial ? 'in' : 'cm',
              validator: Validators.number(min: _imperial ? 32 : 80, max: _imperial ? 102 : 260)),
          const SizedBox(height: Gaps.md),
          NumberField(
              controller: _weight,
              label: 'Current weight',
              suffix: _imperial ? 'lb' : 'kg',
              validator: Validators.number(min: _imperial ? 55 : 25, max: _imperial ? 880 : 400)),
          const SizedBox(height: Gaps.md),
          NumberField(
              controller: _target,
              label: 'Target weight (optional)',
              suffix: _imperial ? 'lb' : 'kg',
              validator: Validators.number(min: _imperial ? 55 : 25, max: _imperial ? 880 : 400)),
        ],
      );

  Widget _goals() => _stepBody(
        index: 2,
        title: 'Experience & goals',
        why: 'Helps IronPulse pick sensible defaults. Nothing here locks you in.',
        children: [
          const Text('Training experience', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: Gaps.sm),
          SegmentedButton<String>(
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(value: 'beginner', label: Text('Beginner')),
              ButtonSegment(value: 'intermediate', label: Text('Intermediate')),
              ButtonSegment(value: 'advanced', label: Text('Advanced')),
            ],
            selected: {if (_p['experience'] != null) _p['experience'] as String},
            onSelectionChanged: (s) => setState(() => _p['experience'] = s.isEmpty ? null : s.first),
          ),
          const SizedBox(height: Gaps.xl),
          const Text('Fitness goals (pick any)', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: Gaps.sm),
          _chips<String>(goalOptions, (g) => _list('goals').contains(g), (g) => _toggleIn('goals', g)),
        ],
      );

  Widget _training() {
    final days = [for (final d in (_p['training_days'] as List? ?? const [])) (d as num).toInt()];
    final time = _p['preferred_gym_time'] as String?;
    return _stepBody(
      index: 3,
      title: 'Your training week',
      why: 'Used to plan your split and (if you enable them) gym reminders.',
      children: [
        const Text('Preferred training days', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: Gaps.sm),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var d = 1; d <= 7; d++)
            FilterChip(
              label: Text(Dates.weekdayName(d, short: true)),
              selected: days.contains(d),
              onSelected: (_) => setState(() {
                days.contains(d) ? days.remove(d) : days.add(d);
                days.sort();
                _p['training_days'] = days;
                if (days.isNotEmpty) _p['weekly_target'] = days.length;
              }),
            ),
        ]),
        const SizedBox(height: Gaps.xl),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Preferred gym time', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(time == null ? 'Not set' : Dates.timeLabel(time)),
          trailing: const Icon(Icons.schedule),
          onTap: () async {
            final parts = (time ?? '18:00').split(':');
            final t = await showTimePicker(
                context: context, initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])));
            if (t != null) setState(() => _p['preferred_gym_time'] = Dates.hhmm(t.hour, t.minute));
          },
        ),
        const SizedBox(height: Gaps.md),
        const Text('Typical workout duration', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: Gaps.sm),
        _chips<int>({30: '30 min', 45: '45 min', 60: '60 min', 75: '75 min', 90: '90+ min'},
            (m) => _p['workout_duration_min'] == m, (m) => _p['workout_duration_min'] = m),
        const SizedBox(height: Gaps.xl),
        Text('Weekly workout target: ${_p['weekly_target'] ?? 3}', style: const TextStyle(fontWeight: FontWeight.w700)),
        Slider(
          value: ((_p['weekly_target'] as num?) ?? 3).toDouble(),
          min: 1,
          max: 7,
          divisions: 6,
          label: '${_p['weekly_target'] ?? 3}',
          onChanged: (v) => setState(() => _p['weekly_target'] = v.round()),
        ),
        const Text('Your streak counts weeks where you hit this target — not daily training.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      ],
    );
  }

  Widget _equipment() => _stepBody(
        index: 4,
        title: 'Equipment & diet',
        why: 'So suggestions match what you can actually use and eat.',
        children: [
          const Text('Available equipment', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: Gaps.sm),
          _chips<String>(equipmentOptions, (e) => _list('equipment').contains(e), (e) => _toggleIn('equipment', e)),
          const SizedBox(height: Gaps.xl),
          const Text('Dietary preferences', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: Gaps.sm),
          _chips<String>(dietOptions, (e) => _list('dietary_preferences').contains(e),
              (e) => _toggleIn('dietary_preferences', e)),
          const SizedBox(height: Gaps.xl),
          TextFormField(
            controller: _allergies,
            decoration: const InputDecoration(labelText: 'Food allergies (optional)', hintText: 'e.g. peanuts, shellfish'),
            validator: Validators.maxLength(300),
          ),
        ],
      );

  Widget _nutrition() => _stepBody(
        index: 5,
        title: 'Nutrition targets',
        why: 'Optional. IronPulse never sets calorie targets for you automatically — use numbers from your coach, '
            'dietitian or your own plan. You can turn targets off at any time.',
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Track against daily targets'),
            value: _targetsOn,
            onChanged: (v) => setState(() => _targetsOn = v),
          ),
          if (_targetsOn) ...[
            const SizedBox(height: Gaps.md),
            NumberField(controller: _protein, label: 'Daily protein', suffix: 'g', validator: Validators.number(min: 0, max: 600)),
            const SizedBox(height: Gaps.md),
            NumberField(controller: _calories, label: 'Daily calories', suffix: 'kcal', validator: Validators.number(min: 0, max: 10000)),
          ],
        ],
      );
}
