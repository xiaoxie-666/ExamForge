package com.examforge.exam.mapper;

import com.examforge.exam.entity.ExamEntity;

/**
 * Projection used by candidate admission. Extending ExamEntity lets MyBatis
 * map the exam columns and the additional candidate status in one query.
 */
public class ExamAdmissionRow extends ExamEntity {
    private Integer candidateStatus;

    public Integer getCandidateStatus() {
        return candidateStatus;
    }

    public void setCandidateStatus(Integer candidateStatus) {
        this.candidateStatus = candidateStatus;
    }
}
