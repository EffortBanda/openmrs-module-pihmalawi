/************************************************************************
  CREATES A TEMPORARY TABLE OF ALL NCD ENROLLMENTS FOR EACH PATIENT
  EXCLUDES VOIDED, AND ADDS IN THE RELEVANT IDENTIFIERS THAT ARE
  ALSO ASSOCIATED WITH THE LOCATION OF THE ENROLLMENT

  REQUIRES: program_by_uuid, identifier_type_by_uuid, state_by_uuid
*************************************************************************/

DROP PROCEDURE IF EXISTS create_mw_ncd_enrollment;
#

CREATE PROCEDURE create_mw_ncd_enrollment(IN _endDate DATE)
BEGIN

    drop temporary table if exists mw_ncd_enrollment;
    create temporary table mw_ncd_enrollment
    (
        enrollment_id  int primary key,
        patient_id     int,
        location_id    int,
        ncd_number     varchar(20),
        date_enrolled  date,
        date_completed date,
        active         boolean,
        advanced_care  boolean
    );

    drop temporary table if exists mw_ncd_enrollment_status;
    create temporary table mw_ncd_enrollment_status
    (
        enrollment_status_id int primary key,
        enrollment_id        int,
        patient_id           int,
        location_id          int,
        state_id             int,
        state_name           varchar(100),
        start_date           date,
        end_date             date,
        num_from_start       int,
        num_from_end         int
    );

    set @ncdNumber = identifier_type_by_uuid('11a76c3e-1db8-4d16-9252-9a18b5ed1843');
    set @ncdProgram = program_by_uuid('6685164a-977f-11e1-8993-905e29aff6c1');
    set @onTxStatus = state_by_uuid('66882650-977f-11e1-8993-905e29aff6c1');
    set @advancedStatus = state_by_uuid('7c4d2e56-c8c2-11e8-9bc6-0242ac110001');

    -- ENROLLMENT TABLE POPULATION

    insert into mw_ncd_enrollment (enrollment_id, patient_id, location_id, date_enrolled, date_completed, active)
    select pp.patient_program_id,
           pp.patient_id,
           pp.location_id,
           pp.date_enrolled,
           pp.date_completed,
           (date(pp.date_enrolled) <= @endDate &&
            (pp.date_completed is null or date(pp.date_completed) >= @endDate)) as active
    from patient_program pp
             inner join mw_patient p on pp.patient_id = p.patient_id
    where pp.voided = 0
      and pp.program_id = @ncdProgram;

    -- IDENTIFIERS ASSOCIATED WITH THE LOCATION OF THE ENROLLMENT

    update mw_ncd_enrollment e
        inner join
        (select patient_id, location_id, identifier
         from patient_identifier pi
         where pi.voided = 0
           and pi.identifier_type = @ncdNumber
         order by pi.preferred asc,
                  pi.date_created asc) pi
        on e.patient_id = pi.patient_id and e.location_id = pi.location_id
    set e.ncd_number = pi.identifier;

    -- STATUS TABLE POPULATION

    insert into mw_ncd_enrollment_status (enrollment_status_id, enrollment_id, patient_id, location_id, state_id,
                                          start_date, end_date)
    select ps.patient_state_id,
           ps.patient_program_id,
           e.patient_id,
           e.location_id,
           ps.state,
           ps.start_date,
           ps.end_date
    from patient_state ps
             inner join mw_ncd_enrollment e on e.enrollment_id = ps.patient_program_id
    where ps.voided = 0;

    -- DISPLAY NAME FOR EACH STATE

    update mw_ncd_enrollment_status s
        inner join program_workflow_state pws on program_workflow_state_id = s.state_id
        inner join concept_name cn on cn.concept_id = pws.concept_id and cn.locale = 'en' and
                                      cn.concept_name_type = 'FULLY_SPECIFIED'
    set s.state_name = cn.name;

    -- SEQUENCE NUMBERS THAT ALLOW US TO EASILY RETRIEVE SPECIFIC OCCURANCES (EG. CURRENT)

    drop temporary table if exists mw_state_seq;
    create temporary table mw_state_seq
    (
        enrollment_status_id int primary key,
        patient_id           int,
        num_from_start       int,
        num_from_end         int
    );

    set @row_number = 0;
    set @patient_id = 0;

    insert into mw_state_seq (enrollment_status_id, patient_id, num_from_start)
    select s.enrollment_status_id,
           s.patient_id,
           s.num
    from (
             select @row_number := if(@patient_id = patient_id, @row_number + 1, 1) as num,
                    @patient_id := patient_id                                       as patient_id,
                    enrollment_status_id
             from mw_ncd_enrollment_status
             order by patient_id,
                      start_date asc,
                      if(end_date is null, 1, 0) asc,
                      end_date asc,
                      enrollment_status_id asc
         ) s;

    set @row_number = 0;
    set @patient_id = 0;

    update mw_state_seq r
        inner join (
            select s.enrollment_status_id,
                   s.num
            from (
                     select @row_number := if(@patient_id = patient_id, @row_number + 1, 1) as num,
                            @patient_id := patient_id                                       as patient_id,
                            enrollment_status_id
                     from mw_ncd_enrollment_status
                     order by patient_id,
                              start_date desc,
                              if(end_date is null, 1, 0) desc,
                              end_date desc,
                              enrollment_status_id desc
                 ) s
        ) ri on r.enrollment_status_id = ri.enrollment_status_id
    set r.num_from_end = ri.num;

    update mw_ncd_enrollment_status s
        inner join mw_state_seq r on s.enrollment_status_id = r.enrollment_status_id
    set s.num_from_start = r.num_from_start,
        s.num_from_end   = r.num_from_end;

    drop table mw_state_seq;

    -- ACTIVE BOOLEAN FLAGS FOR EACH STATE

    update mw_ncd_enrollment e
        inner join mw_ncd_enrollment_status s on e.enrollment_id = s.enrollment_id
    set e.active = true
    where s.num_from_end = 1
      and (s.state_id = @onTxStatus or s.state_id = @advancedStatus);

    update mw_ncd_enrollment e
        inner join mw_ncd_enrollment_status s on e.enrollment_id = s.enrollment_id
    set e.advanced_care = true
    where s.num_from_end = 1
      and s.state_id = @advancedStatus;

END
#
