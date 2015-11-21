package org.openmrs.module.pihmalawi.metadata.deploy.bundle;

import org.openmrs.module.metadatadeploy.bundle.AbstractMetadataBundle;
import org.springframework.stereotype.Component;

import static org.openmrs.module.metadatadeploy.bundle.CoreConstructors.visitType;

/**
 * This was copied from pihcore on 2015-Sep-21.
 */
@Component
public class VisitTypeBundle extends AbstractMetadataBundle {

    public static final class VisitTypes {
        public static final String CLINIC_OR_HOSPITAL_VISIT = "f01c54cb-2225-471a-9cd5-d348552c337c";
    }

    @Override
    public void install() throws Exception {
        install(visitType("Clinic or Hospital Visit", "Patient visits the clinic/hospital (as opposed to a home visit, or telephone contact)", VisitTypes.CLINIC_OR_HOSPITAL_VISIT));
    }
}
