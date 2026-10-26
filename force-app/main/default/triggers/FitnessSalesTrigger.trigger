trigger FitnessSalesTrigger on Sales_Transaction__c (before insert, before update, after insert, after update) {
    if (Trigger.isBefore) FitnessSalesService.calculateCommissions(Trigger.new);
    if (Trigger.isAfter) FitnessSalesService.processQualifiedSales(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
}
