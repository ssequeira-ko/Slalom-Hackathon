public without sharing class FitnessSalesService {
    private static Boolean processing = false;

    public static void calculateCommissions(List<Sales_Transaction__c> rows) {
        Set<Id> memberIds = new Set<Id>();
        for (Sales_Transaction__c s : rows) if (s.Sales_Team_Member__c != null) memberIds.add(s.Sales_Team_Member__c);
        Map<Id, Sales_Team_Member__c> members = new Map<Id, Sales_Team_Member__c>([
            SELECT Id, Sponsor__c, Direct_Commission_Rate__c, Override_Commission_Rate__c
            FROM Sales_Team_Member__c WHERE Id IN :memberIds
        ]);
        Map<Id, Sales_Team_Member__c> sponsors = new Map<Id, Sales_Team_Member__c>();
        Set<Id> sponsorIds = new Set<Id>();
        for (Sales_Team_Member__c m : members.values()) if (m.Sponsor__c != null) sponsorIds.add(m.Sponsor__c);
        if (!sponsorIds.isEmpty()) sponsors = new Map<Id, Sales_Team_Member__c>([
            SELECT Id, Override_Commission_Rate__c FROM Sales_Team_Member__c WHERE Id IN :sponsorIds
        ]);
        for (Sales_Transaction__c s : rows) {
            Sales_Team_Member__c m = members.get(s.Sales_Team_Member__c);
            Decimal amount = s.Amount__c == null ? 0 : s.Amount__c;
            Decimal directRate = m == null || m.Direct_Commission_Rate__c == null ? 20 : m.Direct_Commission_Rate__c;
            s.Direct_Commission__c = (amount * directRate / 100).setScale(2);
            Decimal overrideRate = 0;
            if (m != null && m.Sponsor__c != null && sponsors.containsKey(m.Sponsor__c)) {
                overrideRate = sponsors.get(m.Sponsor__c).Override_Commission_Rate__c == null ? 5 : sponsors.get(m.Sponsor__c).Override_Commission_Rate__c;
            }
            s.Override_Commission__c = (amount * overrideRate / 100).setScale(2);
        }
    }

    public static void processQualifiedSales(List<Sales_Transaction__c> rows, Map<Id, Sales_Transaction__c> oldMap) {
        if (processing) return;
        processing = true;
        try {
            Set<Id> categoryNames = new Set<Id>();
            Set<String> categories = new Set<String>();
            for (Sales_Transaction__c s : rows) {
                Boolean wasQualified = oldMap != null && oldMap.containsKey(s.Id) && oldMap.get(s.Id).Status__c == 'Qualified';
                if (s.Status__c == 'Qualified' && !wasQualified && s.Points_Awarded__c == null) categories.add(s.Product_Category__c);
            }
            if (categories.isEmpty()) return;
            Map<String, Decimal> rates = new Map<String, Decimal>();
            for (Points_Rule__c r : [SELECT Product_Category__c, Points_Per_Dollar__c FROM Points_Rule__c WHERE Active__c = true AND Product_Category__c IN :categories]) rates.put(r.Product_Category__c, r.Points_Per_Dollar__c);
            List<Point_Entry__c> entries = new List<Point_Entry__c>();
            List<Sales_Transaction__c> updates = new List<Sales_Transaction__c>();
            Map<Id, Decimal> pointsByMember = new Map<Id, Decimal>();
            for (Sales_Transaction__c s : rows) {
                Boolean wasQualified = oldMap != null && oldMap.containsKey(s.Id) && oldMap.get(s.Id).Status__c == 'Qualified';
                if (s.Status__c != 'Qualified' || wasQualified || s.Points_Awarded__c != null || s.Sales_Team_Member__c == null) continue;
                Decimal rate = rates.containsKey(s.Product_Category__c) ? rates.get(s.Product_Category__c) : 0;
                Decimal pts = ((s.Amount__c == null ? 0 : s.Amount__c) * rate).setScale(0, RoundingMode.DOWN);
                if (pts <= 0) continue;
                entries.add(new Point_Entry__c(Sales_Team_Member__c=s.Sales_Team_Member__c, Sales_Transaction__c=s.Id, Points__c=pts, Reason__c='Qualified sale: '+s.Product_Category__c));
                updates.add(new Sales_Transaction__c(Id=s.Id, Points_Awarded__c=pts));
                pointsByMember.put(s.Sales_Team_Member__c, (pointsByMember.containsKey(s.Sales_Team_Member__c) ? pointsByMember.get(s.Sales_Team_Member__c) : 0) + pts);
            }
            if (!entries.isEmpty()) insert entries;
            if (!updates.isEmpty()) update updates;
            if (pointsByMember.isEmpty()) return;
            List<Sales_Team_Member__c> changed = [SELECT Id, Total_Points__c, MVP_Status__c FROM Sales_Team_Member__c WHERE Id IN :pointsByMember.keySet() FOR UPDATE];
            for (Sales_Team_Member__c m : changed) m.Total_Points__c = (m.Total_Points__c == null ? 0 : m.Total_Points__c) + pointsByMember.get(m.Id);
            update changed;
            grantAwards(changed);
            checkMvp(changed);
        } finally { processing = false; }
    }

    private static void grantAwards(List<Sales_Team_Member__c> members) {
        Set<Id> mids = new Map<Id, Sales_Team_Member__c>(members).keySet();
        Map<Id, Set<Id>> already = new Map<Id, Set<Id>>();
        for (Member_Award__c ma : [SELECT Sales_Team_Member__c, Award_Definition__c FROM Member_Award__c WHERE Sales_Team_Member__c IN :mids]) {
            if (!already.containsKey(ma.Sales_Team_Member__c)) already.put(ma.Sales_Team_Member__c, new Set<Id>());
            already.get(ma.Sales_Team_Member__c).add(ma.Award_Definition__c);
        }
        List<Member_Award__c> grants = new List<Member_Award__c>();
        for (Award_Definition__c a : [SELECT Id, Points_Threshold__c FROM Award_Definition__c WHERE Active__c = true]) {
            for (Sales_Team_Member__c m : members) if (m.Total_Points__c >= a.Points_Threshold__c && (!already.containsKey(m.Id) || !already.get(m.Id).contains(a.Id))) grants.add(new Member_Award__c(Sales_Team_Member__c=m.Id, Award_Definition__c=a.Id, Awarded_On__c=Date.today()));
        }
        if (!grants.isEmpty()) insert grants;
    }

    private static void checkMvp(List<Sales_Team_Member__c> members) {
        List<Program_Settings__c> settings = [SELECT MVP_Threshold_Points__c, Active__c FROM Program_Settings__c WHERE Active__c=true ORDER BY CreatedDate DESC LIMIT 1];
        Program_Settings__c setting = settings.isEmpty() ? null : settings[0];
        if (setting == null || setting.Active__c != true || setting.MVP_Threshold_Points__c == null) return;
        List<Id> qualified = new List<Id>();
        for (Sales_Team_Member__c m : members) if (m.Total_Points__c >= setting.MVP_Threshold_Points__c && m.MVP_Status__c != 'Sent' && m.MVP_Status__c != 'Pending') qualified.add(m.Id);
        if (!qualified.isEmpty()) {
            System.enqueueJob(new MvpQualificationJob(qualified));
            List<Sales_Team_Member__c> pending = new List<Sales_Team_Member__c>();
            for (Id id : qualified) pending.add(new Sales_Team_Member__c(Id=id, MVP_Status__c='Pending'));
            update pending;
        }
    }
}
