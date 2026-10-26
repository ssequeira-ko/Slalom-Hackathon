public with sharing class MvpQualificationJob implements Queueable, Database.AllowsCallouts {
    private List<Id> memberIds;
    public MvpQualificationJob(List<Id> ids) { memberIds = ids; }
    public void execute(QueueableContext context) {
        List<Sales_Team_Member__c> members = [SELECT Id, Name, Total_Points__c, MVP_Status__c, Contact__r.Email, Contact__r.Name FROM Sales_Team_Member__c WHERE Id IN :memberIds];
        for (Sales_Team_Member__c m : members) {
            HttpRequest req = new HttpRequest(); req.setEndpoint('callout:MVP_Tracking/qualifications'); req.setMethod('POST'); req.setHeader('Content-Type','application/json');
            req.setBody(JSON.serialize(new Map<String,Object>{'salesforceMemberId'=>m.Id, 'name'=>m.Contact__r.Name, 'email'=>m.Contact__r.Email, 'points'=>m.Total_Points__c, 'qualifiedAt'=>String.valueOf(DateTime.now())}));
            try {
                HttpResponse res = new Http().send(req);
                m.MVP_Status__c = (res.getStatusCode() >= 200 && res.getStatusCode() < 300) ? 'Sent' : 'Error';
                if (m.MVP_Status__c == 'Sent') m.MVP_Last_Sent__c = System.now();
            } catch (Exception e) { m.MVP_Status__c = 'Error'; }
        }
        if (!members.isEmpty()) update members;
    }
}
