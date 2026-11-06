from datetime import date, timedelta

from app.services.gamification import compute_streaks, epley_1rm, level_for


def test_levels():
    assert level_for(0)["name"] == "Rookie"
    lv = level_for(300)
    assert lv["name"] == "Gym Beginner" and lv["next_level_xp"] == 750
    assert 0 < lv["progress"] < 1
    top = level_for(99999)
    assert top["name"] == "Elite Grinder" and top["next_level_xp"] is None and top["progress"] == 1.0


def test_streak_counts_weeks_not_days_and_ignores_rest_days():
    today = date(2026, 10, 25)  # a Sunday
    mon = today - timedelta(days=today.weekday())
    dates = []
    for w in range(3):  # three consecutive weeks, three sessions each, rest days between
        base = mon - timedelta(weeks=w)
        dates += [base, base + timedelta(days=2), base + timedelta(days=4)]
    s = compute_streaks(dates, weekly_target=3, today=today)
    assert s["current_streak_weeks"] == 3 and s["longest_streak_weeks"] == 3 and s["total_workouts"] == 9


def test_unfinished_current_week_does_not_break_streak():
    today = date(2026, 10, 21)  # Wednesday
    last_week = today - timedelta(days=7)
    s = compute_streaks([last_week, last_week + timedelta(days=1)], weekly_target=2, today=today)
    assert s["current_streak_weeks"] == 1 and s["this_week_workouts"] == 0


def test_missed_week_resets_current_but_keeps_longest():
    today = date(2026, 10, 25)
    old = [today - timedelta(weeks=3), today - timedelta(weeks=4)]
    s = compute_streaks(old, weekly_target=1, today=today)
    assert s["current_streak_weeks"] == 0 and s["longest_streak_weeks"] == 2


def test_epley():
    assert round(epley_1rm(100, 5), 1) == 116.7
