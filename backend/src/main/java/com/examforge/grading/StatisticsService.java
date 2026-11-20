package com.examforge.grading;

import com.examforge.common.ApiDtos.ExamStatisticsDetail;
import com.examforge.common.ApiDtos.ExamStatisticsSummary;
import com.examforge.common.ApiDtos.ScoreDistribution;
import com.examforge.common.ApiDtos.ScoreRanking;
import com.examforge.common.BusinessException;
import com.examforge.grading.mapper.ExamStatisticsRow;
import com.examforge.grading.mapper.ScoreRankingRow;
import com.examforge.grading.mapper.StatisticsMapper;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.List;

@Service
public class StatisticsService {

    private static final BigDecimal PASS_RATIO = new BigDecimal("0.60");

    private final StatisticsMapper statistics;

    public StatisticsService(StatisticsMapper statistics) {
        this.statistics = statistics;
    }

    public List<ExamStatisticsSummary> list() {
        return statistics.selectExamStatistics().stream()
                .map(this::buildSummary)
                .toList();
    }

    public ExamStatisticsDetail detail(Long examId) {
        ExamStatisticsRow row = statistics.selectExamStatisticsById(examId);
        if (row == null) {
            throw new BusinessException("考试不存在");
        }

        List<ScoreRankingRow> completed = statistics.selectCompletedScores(examId);
        ExamStatisticsSummary summary = buildSummary(row, completed);
        List<ScoreDistribution> distribution = buildDistribution(row.getTotalScore(), completed);
        List<ScoreRanking> ranking = new ArrayList<>(completed.size());

        long rank = 1;
        for (ScoreRankingRow item : completed) {
            ranking.add(new ScoreRanking(
                    rank++,
                    item.getAttemptId(),
                    item.getUserId(),
                    item.getStudentName(),
                    money(item.getObjectiveScore()),
                    money(item.getSubjectiveScore()),
                    money(item.getTotalScore()),
                    item.getGradedAt()
            ));
        }

        return new ExamStatisticsDetail(summary, distribution, ranking);
    }

    private ExamStatisticsSummary buildSummary(ExamStatisticsRow row) {
        return buildSummary(row, statistics.selectCompletedScores(row.getExamId()));
    }

    private ExamStatisticsSummary buildSummary(
            ExamStatisticsRow row,
            List<ScoreRankingRow> completed) {

        long graded = row.getGraded();
        long pending = Math.max(0L, row.getSubmitted() - graded);

        BigDecimal passRate = BigDecimal.ZERO;
        BigDecimal totalScore = money(row.getTotalScore());

        if (graded > 0 && totalScore.compareTo(BigDecimal.ZERO) > 0) {
            BigDecimal passLine = totalScore.multiply(PASS_RATIO);
            long passed = completed.stream()
                    .filter(item -> item.getTotalScore() != null
                            && item.getTotalScore().compareTo(passLine) >= 0)
                    .count();

            passRate = BigDecimal.valueOf(passed)
                    .multiply(BigDecimal.valueOf(100))
                    .divide(BigDecimal.valueOf(graded), 2, RoundingMode.HALF_UP);
        }

        return new ExamStatisticsSummary(
                row.getExamId(),
                row.getExamTitle(),
                row.getExamStatus(),
                totalScore,
                row.getParticipants(),
                row.getSubmitted(),
                graded,
                pending,
                money(row.getAverageScore()),
                money(row.getHighestScore()),
                money(row.getLowestScore()),
                passRate
        );
    }

    private List<ScoreDistribution> buildDistribution(
            BigDecimal totalScore,
            List<ScoreRankingRow> completed) {

        String[] ranges = {"90%-100%", "80%-89%", "70%-79%", "60%-69%", "0%-59%"};
        long[] counts = new long[ranges.length];

        if (totalScore == null || totalScore.compareTo(BigDecimal.ZERO) <= 0) {
            return List.of();
        }

        for (ScoreRankingRow item : completed) {
            if (item.getTotalScore() == null) {
                continue;
            }

            BigDecimal ratio = item.getTotalScore()
                    .divide(totalScore, 6, RoundingMode.HALF_UP)
                    .multiply(BigDecimal.valueOf(100));

            int index;
            if (ratio.compareTo(BigDecimal.valueOf(90)) >= 0) {
                index = 0;
            } else if (ratio.compareTo(BigDecimal.valueOf(80)) >= 0) {
                index = 1;
            } else if (ratio.compareTo(BigDecimal.valueOf(70)) >= 0) {
                index = 2;
            } else if (ratio.compareTo(BigDecimal.valueOf(60)) >= 0) {
                index = 3;
            } else {
                index = 4;
            }
            counts[index]++;
        }

        List<ScoreDistribution> result = new ArrayList<>(ranges.length);
        BigDecimal denominator = BigDecimal.valueOf(completed.size());

        for (int i = 0; i < ranges.length; i++) {
            BigDecimal rate = denominator.compareTo(BigDecimal.ZERO) == 0
                    ? BigDecimal.ZERO
                    : BigDecimal.valueOf(counts[i])
                    .multiply(BigDecimal.valueOf(100))
                    .divide(denominator, 2, RoundingMode.HALF_UP);

            result.add(new ScoreDistribution(ranges[i], counts[i], rate));
        }
        return result;
    }

    private BigDecimal money(BigDecimal value) {
        return value == null
                ? BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP)
                : value.setScale(2, RoundingMode.HALF_UP);
    }
}
